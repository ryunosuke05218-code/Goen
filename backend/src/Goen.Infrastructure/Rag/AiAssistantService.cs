using System.Text.Json;
using Goen.Infrastructure.ExternalAi;
using Goen.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;

namespace Goen.Infrastructure.Rag;

public record AssistantHint(Guid PersonId, string PersonName, string Reason, string Excerpt);
public record AssistantRouteStep(Guid PersonId, string PersonName, string? RelationTypeFromPrevious);
public record AssistantRoute(List<AssistantRouteStep> Steps);
public record AssistantResult(string Answer, List<AssistantRoute> Routes, List<AssistantHint> Hints);

// 「AI指示」機能: 自然文の依頼から (1) RAGハイブリッド検索によるヒント、(2) person_relationsのBFSによる
// 紹介経路、を実データのみで組み立て、それをもとにLLMへ自然文の回答生成のみを行わせる。
// 経路・ヒントに含まれる人物はすべてDB由来の実在データであり、LLMが人物名を創作することはない
// （route.Steps / hints は本サービスが構築し、LLMには「説明文の作成」のみを依頼する）。
//
// 外部AI（Ollama等）やRAG検索が一時的に失敗しても画面全体を500にしないよう、各段階を個別にtry-catchし、
// 失敗した段階は空の結果として扱う（可能な範囲の情報だけを返す）。
public class AiAssistantService
{
    private const int RagHitLimit = 20;
    private const int MaxHints = 8;

    private readonly GoenDbContext _db;
    private readonly IEmbeddingService _embedding;
    private readonly ILlmService _llm;
    private readonly RagChunkRepository _ragRepository;
    private readonly ILogger<AiAssistantService> _logger;

    public AiAssistantService(
        GoenDbContext db, IEmbeddingService embedding, ILlmService llm, RagChunkRepository ragRepository,
        ILogger<AiAssistantService> logger)
    {
        _db = db;
        _embedding = embedding;
        _llm = llm;
        _ragRepository = ragRepository;
        _logger = logger;
    }

    public async Task<AssistantResult> AskAsync(Guid ownerUserId, Guid orgId, string instruction, CancellationToken ct)
    {
        List<AssistantHint> hints;
        try
        {
            hints = await SearchHintsAsync(ownerUserId, instruction, ct);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "RAGヒント検索に失敗しました（埋め込みAPI未接続、またはrag_chunksのスキーマ不整合の可能性）");
            hints = new List<AssistantHint>();
        }

        List<AssistantRoute> routes = new();
        try
        {
            var targetGuess = await ExtractTargetAsync(instruction, ct);
            if (targetGuess is (not null, _) or (_, not null))
            {
                var (companyId, personId) = await ResolveTargetAsync(orgId, targetGuess, ct);
                if (companyId is not null || personId is not null)
                {
                    routes = await FindRoutesAsync(ownerUserId, orgId, companyId, personId, ct);
                }
            }
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "経路探索に失敗しました");
        }

        var answer = await ComposeAnswerAsync(instruction, hints, routes, ct);

        return new AssistantResult(answer, routes, hints);
    }

    private async Task<List<AssistantHint>> SearchHintsAsync(Guid ownerUserId, string instruction, CancellationToken ct)
    {
        var queryVector = await _embedding.EmbedQueryAsync(instruction, ct);
        var hits = await _ragRepository.SearchAsync(ownerUserId, queryVector, instruction, RagHitLimit, ct);
        if (hits.Count == 0) return new List<AssistantHint>();

        var bestPerPerson = hits
            .GroupBy(h => h.PersonId)
            .Select(g => g.OrderByDescending(h => h.Score).First())
            .OrderByDescending(h => h.Score)
            .Take(MaxHints)
            .ToList();

        var personIds = bestPerPerson.Select(h => h.PersonId).ToList();
        var names = await _db.PersonsRead
            .Where(r => personIds.Contains(r.PersonId))
            .ToDictionaryAsync(r => r.PersonId, r => r.FullName, ct);

        return bestPerPerson
            .Where(h => names.ContainsKey(h.PersonId))
            .Select(h => new AssistantHint(h.PersonId, names[h.PersonId], ReasonFor(h.SourceType), Truncate(h.Content, 120)))
            .ToList();
    }

    private static string ReasonFor(string sourceType) => sourceType switch
    {
        "transcript" => "過去の会話記録に関連する記載があります",
        "note" => "接点メモに関連する記載があります",
        "card" => "AI人物カルテの内容と関連しています",
        "profile" => "プロフィール情報（会社・地域等）が関連しています",
        _ => "関連する記録があります",
    };

    private static string Truncate(string text, int maxLength) =>
        text.Length <= maxLength ? text : text[..maxLength] + "…";

    private async Task<(string? CompanyName, string? PersonName)> ExtractTargetAsync(string instruction, CancellationToken ct)
    {
        const string systemPrompt = """
            ユーザーの依頼文から、ユーザーが「つながりたい」「紹介してほしい」と考えている対象の
            会社名または人物名を抽出してください。

            必ず次のJSON形式のみで出力してください（説明文や前置きは不要）:
            {"targetCompanyName": "会社名またはnull", "targetPersonName": "人物名またはnull"}

            該当する記載がなければ両方nullにしてください。推測で埋めないでください。
            """;

        try
        {
            var text = await _llm.ComposeTextAsync(systemPrompt, instruction, ct);
            var json = LenientJson.Parse(text);
            var company = GetString(json, "targetCompanyName");
            var person = GetString(json, "targetPersonName");
            return (company, person);
        }
        catch
        {
            // 抽出に失敗した場合は経路探索をスキップし、RAGヒントのみ返す
            return (null, null);
        }
    }

    private static string? GetString(JsonElement element, string propertyName)
    {
        if (!element.TryGetProperty(propertyName, out var value) || value.ValueKind != JsonValueKind.String)
        {
            return null;
        }
        var s = value.GetString();
        return string.IsNullOrWhiteSpace(s) ? null : s;
    }

    private async Task<(Guid? CompanyId, Guid? PersonId)> ResolveTargetAsync(
        Guid orgId, (string? CompanyName, string? PersonName) guess, CancellationToken ct)
    {
        Guid? companyId = null;
        Guid? personId = null;

        if (guess.CompanyName is not null)
        {
            companyId = await _db.Companies
                .Where(c => EF.Functions.ILike(c.CompanyName, $"%{guess.CompanyName}%"))
                .Select(c => (Guid?)c.CompanyId)
                .FirstOrDefaultAsync(ct);
        }
        if (guess.PersonName is not null)
        {
            personId = await _db.Persons
                .Where(p => p.OrgId == orgId && EF.Functions.ILike(p.FullName, $"%{guess.PersonName}%"))
                .Select(p => (Guid?)p.PersonId)
                .FirstOrDefaultAsync(ct);
        }

        return (companyId, personId);
    }

    // 自分の直接の人脈を起点に、person_relationsを辿ってターゲット（人物 or 会社に所属する人物）への
    // 最短経路をBFSで探索する。エッジは組織スコープで一括ロードし、メモリ上で探索する。
    private async Task<List<AssistantRoute>> FindRoutesAsync(
        Guid ownerUserId, Guid orgId, Guid? targetCompanyId, Guid? targetPersonId, CancellationToken ct)
    {
        var myPersonIds = await _db.Persons
            .Where(p => p.OrgId == orgId && p.OwnerUserId == ownerUserId)
            .Select(p => p.PersonId)
            .ToListAsync(ct);
        if (myPersonIds.Count == 0) return new List<AssistantRoute>();

        var myPersonIdSet = myPersonIds.ToHashSet();

        var targetIds = new HashSet<Guid>();
        if (targetPersonId is { } tp) targetIds.Add(tp);
        if (targetCompanyId is { } tc)
        {
            var companyPeople = await _db.Persons
                .Where(p => p.OrgId == orgId && p.CompanyId == tc)
                .Select(p => p.PersonId)
                .ToListAsync(ct);
            foreach (var id in companyPeople) targetIds.Add(id);
        }
        targetIds.ExceptWith(myPersonIdSet); // 既に自分の直接の人脈なら経路探索は不要（ヒント側で拾われる）
        if (targetIds.Count == 0) return new List<AssistantRoute>();

        var edges = await _db.PersonRelations
            .Where(r => r.OrgId == orgId)
            .Select(r => new { r.FromPersonId, r.ToPersonId, r.RelationType })
            .ToListAsync(ct);

        var adjacency = new Dictionary<Guid, List<(Guid To, string Type)>>();
        void AddEdge(Guid from, Guid to, string type)
        {
            if (!adjacency.TryGetValue(from, out var list))
            {
                list = new List<(Guid, string)>();
                adjacency[from] = list;
            }
            list.Add((to, type));
        }
        foreach (var e in edges)
        {
            AddEdge(e.FromPersonId, e.ToPersonId, e.RelationType);
            AddEdge(e.ToPersonId, e.FromPersonId, e.RelationType); // 経路探索では向きを問わない
        }

        var visited = new HashSet<Guid>(myPersonIdSet);
        var queue = new Queue<Guid>(myPersonIds);
        var cameFrom = new Dictionary<Guid, (Guid From, string Type)>();
        Guid? reached = null;

        while (queue.Count > 0 && reached is null)
        {
            var current = queue.Dequeue();
            if (targetIds.Contains(current))
            {
                reached = current;
                break;
            }
            if (!adjacency.TryGetValue(current, out var neighbors)) continue;
            foreach (var (next, type) in neighbors)
            {
                if (!visited.Add(next)) continue;
                cameFrom[next] = (current, type);
                queue.Enqueue(next);
            }
        }

        if (reached is null) return new List<AssistantRoute>();

        var pathIds = new List<Guid>();
        var relTypes = new List<string?> { null };
        var cursor = reached.Value;
        while (!myPersonIdSet.Contains(cursor) && cameFrom.TryGetValue(cursor, out var prev))
        {
            pathIds.Add(cursor);
            relTypes.Add(prev.Type);
            cursor = prev.From;
        }
        pathIds.Add(cursor); // 起点（自分の直接の人脈）
        pathIds.Reverse();
        relTypes.RemoveAt(relTypes.Count - 1);
        relTypes.Reverse();

        var names = await _db.PersonsRead
            .Where(r => pathIds.Contains(r.PersonId))
            .ToDictionaryAsync(r => r.PersonId, r => r.FullName, ct);

        var steps = pathIds
            .Select((id, i) => new AssistantRouteStep(id, names.GetValueOrDefault(id, "?"), i < relTypes.Count ? relTypes[i] : null))
            .ToList();

        return new List<AssistantRoute> { new(steps) };
    }

    private async Task<string> ComposeAnswerAsync(string instruction, List<AssistantHint> hints, List<AssistantRoute> routes, CancellationToken ct)
    {
        // 経路もヒントも無い場合、LLM（特にgemma3:4bのような小規模モデル）に空データから
        // 無理に回答させると、依頼内容と無関係な文章や記号の羅列を返すことがあるため、
        // LLMを呼ばずに固定文で応答する（画面上の「経路/ヒントが空」表示と矛盾しないようにする意味もある）。
        if (routes.Count == 0 && hints.Count == 0)
        {
            return "関連しそうな人脈や紹介経路が見つかりませんでした。人物カルテのメモを充実させると、AI指示で拾えるようになる可能性があります。";
        }

        const string systemPrompt = """
            あなたは営業担当者向け人脈管理アプリのAIアシスタントです。
            ユーザーの依頼に対し、以下の「実データ」だけを根拠に、自然な日本語の文章で回答してください。

            重要なルール:
            - 実データに存在しない人物名・会社名を創作してはいけません。
            - 実データの一覧をそのまま書き写す・箇条書き記号や「/」「,」区切りの羅列をそのまま出力する、
              といったことはせず、必ず読みやすい話し言葉の文章にしてください。
            - ユーザーの依頼内容に直接答えることを最優先し、依頼と無関係な情報は書かないでください。
            - 【紹介経路の候補】がある場合は「Aさん経由でBさんに紹介してもらうのがおすすめです」のように
              具体的な経路として提案してください。
            - 【関連しそうな人物】がある場合は「〇〇さんが知っている可能性があります」
              「△△さんとはこのような接点があります」のように触れてください。
            - 3〜6文程度で簡潔にまとめてください。
            """;

        var sections = new List<string> { $"ユーザーの依頼: {instruction}" };

        if (routes.Count > 0)
        {
            var chains = routes.Select(r => string.Join(" → ", r.Steps.Select(s => s.PersonName)));
            sections.Add("【紹介経路の候補】\n" + string.Join("\n", chains.Select(c => $"- {c}")));
        }
        if (hints.Count > 0)
        {
            var lines = hints.Select(h => $"- {h.PersonName}: {h.Reason}（{h.Excerpt}）");
            sections.Add("【関連しそうな人物】\n" + string.Join("\n", lines));
        }

        var userPrompt = string.Join("\n\n", sections);

        try
        {
            return await _llm.ComposeTextAsync(systemPrompt, userPrompt, ct);
        }
        catch (Exception ex)
        {
            return $"AIによる回答生成に失敗しました（{ex.Message}）。下記の検索結果を参考にしてください。";
        }
    }
}
