namespace Goen.Infrastructure.ExternalAi;

// 外部LLM API（I-003）未選定（要件Q-004）のため、開発用のダミー実装を提供する。
// F-010業務ルール: 抽出できなかった項目は空欄とし推測で埋めない、という方針をダミー実装でも踏襲する。
public class MockLlmService : ILlmService
{
    public Task<PersonCardDraft> GeneratePersonCardAsync(
        string fullName,
        IReadOnlyCollection<string> sourceTexts,
        CancellationToken cancellationToken = default)
    {
        var combined = string.Join(" / ", sourceTexts);
        var draft = new PersonCardDraft(
            Summary: $"（ダミー要約）{fullName}氏。{(combined.Length > 0 ? "入力情報より生成。" : "情報が少ないため簡易的な要約です。")}",
            Business: combined.Length > 0 ? "（ダミー）詳細は入力情報を確認してください。" : null,
            Issues: null,
            IntroducerName: null,
            Hobby: null);

        return Task.FromResult(draft);
    }

    public Task<IReadOnlyList<RelationSuggestion>> SuggestRelationsAsync(
        PersonContext target,
        IReadOnlyList<PersonContext> candidates,
        CancellationToken cancellationToken = default)
    {
        // カルテの紹介者欄と氏名が一致する候補のみを単純ルールで提案する（実LLM未接続時の最小限のダミー挙動）
        var suggestions = candidates
            .Where(c => target.IntroducerName is not null && c.FullName.Contains(target.IntroducerName))
            .Select(c => new RelationSuggestion(c.PersonId, "referrer", "（ダミー）カルテの紹介者欄と氏名が一致するため", 3))
            .ToList();

        return Task.FromResult<IReadOnlyList<RelationSuggestion>>(suggestions);
    }

    public Task<string> ComposeTextAsync(string systemPrompt, string userPrompt, CancellationToken cancellationToken = default) =>
        Task.FromResult("（ダミー応答）LLMが未接続のため、検索結果の生データのみ確認してください。");
}
