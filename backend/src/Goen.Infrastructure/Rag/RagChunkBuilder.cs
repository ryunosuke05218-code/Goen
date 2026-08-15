using System.Text.Json;
using Goen.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace Goen.Infrastructure.Rag;

// テーブル設計書 4.2 チャンク化ルールに基づき、ソース種別ごとにRAGチャンクの下書きを組み立てる。
// 'profile' は本実装で追加した種別で、会社名・業種・都道府県・役職等の構造化データを検索対象にするために使う
// （「都道府県などの点をRAG検索で検索」という要件に対応）。
public class RagChunkBuilder
{
    private const int ChunkSize = 700;
    private const int ChunkOverlap = 100;

    private readonly GoenDbContext _db;

    public RagChunkBuilder(GoenDbContext db)
    {
        _db = db;
    }

    public async Task<List<RagChunkDraft>> BuildAsync(string sourceType, Guid sourceId, Guid personId, CancellationToken ct) =>
        sourceType switch
        {
            "profile" => await BuildProfileAsync(personId, ct),
            "card" => await BuildCardAsync(sourceId, ct),
            "transcript" => await BuildTranscriptAsync(sourceId, ct),
            "note" => await BuildNoteAsync(sourceId, ct),
            _ => new List<RagChunkDraft>(),
        };

    private async Task<List<RagChunkDraft>> BuildProfileAsync(Guid personId, CancellationToken ct)
    {
        var row = await _db.Persons
            .Where(p => p.PersonId == personId)
            .Select(p => new
            {
                p.FullName,
                p.FullNameKana,
                p.Department,
                p.JobTitle,
                p.MetPlace,
                p.Version,
                CompanyName = p.Company != null ? p.Company.CompanyName : null,
            })
            .FirstOrDefaultAsync(ct);

        if (row is null) return new List<RagChunkDraft>();

        var profile = await _db.PersonProfiles.Where(x => x.PersonId == personId).FirstOrDefaultAsync(ct);

        // 都道府県マスタから名称を引く（person_profiles.pref_code経由）
        string? prefName = null;
        if (profile?.PrefCode is not null)
        {
            prefName = await _db.Database.SqlQueryRaw<string>(
                "SELECT pref_name FROM m_prefecture WHERE pref_code = {0}", profile.PrefCode)
                .FirstOrDefaultAsync(ct);
        }

        var lines = new List<string>
        {
            $"氏名: {row.FullName}" + (string.IsNullOrWhiteSpace(row.FullNameKana) ? "" : $"（{row.FullNameKana}）"),
        };
        if (!string.IsNullOrWhiteSpace(row.CompanyName)) lines.Add($"会社: {row.CompanyName}");
        if (!string.IsNullOrWhiteSpace(row.Department)) lines.Add($"部署: {row.Department}");
        if (!string.IsNullOrWhiteSpace(row.JobTitle)) lines.Add($"役職: {row.JobTitle}");
        if (!string.IsNullOrWhiteSpace(row.MetPlace)) lines.Add($"出会った場所: {row.MetPlace}");
        if (!string.IsNullOrWhiteSpace(prefName)) lines.Add($"都道府県: {prefName}");
        if (!string.IsNullOrWhiteSpace(profile?.Note)) lines.Add($"メモ: {profile!.Note}");

        var content = string.Join("\n", lines);
        return new List<RagChunkDraft> { new(0, content, row.Version, null) };
    }

    private async Task<List<RagChunkDraft>> BuildCardAsync(Guid cardId, CancellationToken ct)
    {
        var card = await _db.AiPersonCards.Where(c => c.CardId == cardId).FirstOrDefaultAsync(ct);
        if (card is null) return new List<RagChunkDraft>();

        var parts = new List<string>();
        if (!string.IsNullOrWhiteSpace(card.Summary)) parts.Add($"AI要約: {card.Summary}");
        if (!string.IsNullOrWhiteSpace(card.Business)) parts.Add($"事業内容: {card.Business}");
        if (!string.IsNullOrWhiteSpace(card.Issues)) parts.Add($"抱える課題: {card.Issues}");
        if (!string.IsNullOrWhiteSpace(card.Hobby)) parts.Add($"趣味・人柄: {card.Hobby}");
        if (!string.IsNullOrWhiteSpace(card.Strengths)) parts.Add($"強み: {card.Strengths}");

        // カルテは世代ごとに新しいcard_id（＝新しいsource_id）が発行されるため、内容自体は不変。source_versionは常に1でよい。
        var chunks = new List<RagChunkDraft>();
        if (parts.Count > 0)
        {
            chunks.Add(new RagChunkDraft(0, string.Join("\n", parts), 1, card.GeneratedAt));
        }

        // このAI要約の生成時に参照したHPリンク・資料ファイル（InputSourcesJson）を、独立したチャンクとして検索対象に含める。
        // 要約本文と同じチャンクに混ぜると、AI指示（AiAssistantService）が抜粋時に120文字へ切り詰める際に埋もれて
        // LLMに届かなくなるため、あえて別チャンクにして単独でも検索・参照できるようにする。
        var sourcesContent = BuildInputSourcesContent(card.InputSourcesJson);
        if (sourcesContent is not null)
        {
            chunks.Add(new RagChunkDraft(chunks.Count, sourcesContent, 1, card.GeneratedAt));
        }

        return chunks;
    }

    private static string? BuildInputSourcesContent(string? inputSourcesJson)
    {
        if (string.IsNullOrWhiteSpace(inputSourcesJson)) return null;

        JsonDocument doc;
        try
        {
            doc = JsonDocument.Parse(inputSourcesJson);
        }
        catch (JsonException)
        {
            return null;
        }

        using (doc)
        {
            if (doc.RootElement.ValueKind != JsonValueKind.Array) return null;

            var urls = new List<string>();
            var files = new List<string>();
            foreach (var item in doc.RootElement.EnumerateArray())
            {
                var type = item.TryGetProperty("type", out var t) ? t.GetString() : null;
                var value = item.TryGetProperty("value", out var v) ? v.GetString() : null;
                if (string.IsNullOrWhiteSpace(value)) continue;
                if (type == "url") urls.Add(value);
                else if (type == "file") files.Add(value);
            }

            if (urls.Count == 0 && files.Count == 0) return null;

            var lines = new List<string> { "AI要約の参照元:" };
            if (urls.Count > 0) lines.Add($"HPリンク: {string.Join(", ", urls)}");
            if (files.Count > 0) lines.Add($"資料ファイル: {string.Join(", ", files)}");
            return string.Join("\n", lines);
        }
    }

    private async Task<List<RagChunkDraft>> BuildTranscriptAsync(Guid transcriptId, CancellationToken ct)
    {
        var t = await _db.Transcripts.Where(x => x.TranscriptId == transcriptId).FirstOrDefaultAsync(ct);
        if (t is null || string.IsNullOrWhiteSpace(t.Content)) return new List<RagChunkDraft>();

        var occurredAt = await _db.Contacts.Where(c => c.ContactId == t.ContactId).Select(c => (DateTimeOffset?)c.OccurredAt).FirstOrDefaultAsync(ct);

        var windows = SplitWithOverlap(t.Content, ChunkSize, ChunkOverlap);
        var result = new List<RagChunkDraft>();
        for (var i = 0; i < windows.Count; i++)
        {
            result.Add(new RagChunkDraft(i, windows[i], t.Version, occurredAt));
        }
        return result;
    }

    private async Task<List<RagChunkDraft>> BuildNoteAsync(Guid contactId, CancellationToken ct)
    {
        var c = await _db.Contacts.Where(x => x.ContactId == contactId).FirstOrDefaultAsync(ct);
        if (c is null || string.IsNullOrWhiteSpace(c.Note)) return new List<RagChunkDraft>();

        var content = string.IsNullOrWhiteSpace(c.Place) ? c.Note : $"（{c.Place}）{c.Note}";
        return new List<RagChunkDraft> { new(0, content, c.Version, c.OccurredAt) };
    }

    // テーブル設計書 4.2: transcriptは500〜800文字（前後100文字のオーバーラップ付き）で分割する
    internal static List<string> SplitWithOverlap(string text, int chunkSize, int overlap)
    {
        var trimmed = text.Trim();
        if (trimmed.Length <= chunkSize)
        {
            return new List<string> { trimmed };
        }

        var result = new List<string>();
        var step = chunkSize - overlap;
        for (var start = 0; start < trimmed.Length; start += step)
        {
            var length = Math.Min(chunkSize, trimmed.Length - start);
            result.Add(trimmed.Substring(start, length));
            if (start + length >= trimmed.Length) break;
        }
        return result;
    }
}
