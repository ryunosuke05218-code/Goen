using Goen.Infrastructure.ExternalAi;
using Goen.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace Goen.Infrastructure.Messaging;

// F-026 紹介文（例文）作成機能。
// 対象人物のDB上の実データ（会社・役職・AI要約・課題・プロフィールメモ・直近の接点メモ）と、
// 利用者が入力した要件・トーン等の条件をもとに、チャットLLMへ文面の下書き作成のみを依頼する。
// 経路提案・RAGヒント（AiAssistantService）と同じ「実データはアプリが用意し、LLMは文章化のみ行う」設計方針を踏襲する。
public class IntroLetterService
{
    private const int MaxRecentContactNotes = 5;

    private readonly GoenDbContext _db;
    private readonly ILlmService _llm;

    public IntroLetterService(GoenDbContext db, ILlmService llm)
    {
        _db = db;
        _llm = llm;
    }

    public async Task<string> GenerateAsync(
        Guid targetPersonId, Guid orgId, string requirement, string? tone, string? lengthHint, string? additionalNotes,
        CancellationToken ct)
    {
        var person = await _db.Persons
            .Include(p => p.Company)
            .Include(p => p.Profile)
            .FirstOrDefaultAsync(p => p.PersonId == targetPersonId && p.OrgId == orgId, ct);
        if (person is null)
        {
            throw new InvalidOperationException("対象の人物が見つかりません。");
        }

        var card = await _db.AiPersonCards
            .Where(c => c.PersonId == targetPersonId && c.IsLatest)
            .FirstOrDefaultAsync(ct);

        var recentNotes = await _db.Contacts
            .Where(c => c.PersonId == targetPersonId && c.Note != null)
            .OrderByDescending(c => c.OccurredAt)
            .Take(MaxRecentContactNotes)
            .Select(c => c.Note!)
            .ToListAsync(ct);

        var facts = new List<string> { $"氏名: {person.FullName}" };
        if (person.Company is not null) facts.Add($"会社: {person.Company.CompanyName}");
        if (!string.IsNullOrWhiteSpace(person.JobTitle)) facts.Add($"役職: {person.JobTitle}");
        if (!string.IsNullOrWhiteSpace(card?.Summary)) facts.Add($"AI要約: {card!.Summary}");
        if (!string.IsNullOrWhiteSpace(card?.Business)) facts.Add($"事業内容: {card!.Business}");
        if (!string.IsNullOrWhiteSpace(card?.Issues)) facts.Add($"抱えている課題: {card!.Issues}");
        if (!string.IsNullOrWhiteSpace(card?.Hobby)) facts.Add($"趣味・人柄: {card!.Hobby}");
        if (!string.IsNullOrWhiteSpace(person.Profile?.Note)) facts.Add($"人物カルテのメモ: {person.Profile!.Note}");
        foreach (var note in recentNotes)
        {
            facts.Add($"過去の接点メモ: {note}");
        }

        const string systemPrompt = """
            あなたは営業担当者向け人脈管理アプリのAIアシスタントです。
            以下の「対象人物の実データ」と「作成要件」をもとに、そのまま送信できる紹介文・メッセージの下書きを1つ作成してください。

            重要なルール:
            - 実データに存在しない事実（会社名・実績・共通の知人・過去のやり取りなど）を創作してはいけません。
            - 実データの中から、作成要件に関係が深いものだけを選んで自然に盛り込むこと。関係が薄い情報は無理に使わない。
            - 実データが少ない場合は、無理に個人的な内容を作らず、一般的で失礼のない文面にすること。
            - 挨拶から始まる、そのまま送れる本文のみを出力すること（前置き・説明・タイトルは不要）。
            - トーン・文字数の指定があれば従うこと。
            """;

        var userPrompt = $"""
            【対象人物の実データ】
            {string.Join("\n", facts)}

            【作成要件】
            {requirement}

            【トーン】{(string.IsNullOrWhiteSpace(tone) ? "指定なし（丁寧な標準的トーン）" : tone)}
            【文字数目安】{(string.IsNullOrWhiteSpace(lengthHint) ? "指定なし" : lengthHint)}
            【補足条件】{(string.IsNullOrWhiteSpace(additionalNotes) ? "なし" : additionalNotes)}
            """;

        return await _llm.ComposeTextAsync(systemPrompt, userPrompt, ct);
    }
}
