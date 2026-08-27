namespace Goen.Infrastructure.ExternalAi;

// 外部LLM API（I-003）未選定（要件Q-004）のため、開発用のダミー実装を提供する。
// F-010業務ルール: 抽出できなかった項目は空欄とし推測で埋めない、という方針をダミー実装でも踏襲する。
public class MockLlmService : ILlmService
{
    public Task<PersonCardDraft> GeneratePersonCardAsync(
        string fullName,
        IReadOnlyCollection<string> sourceTexts,
        IReadOnlyCollection<AttachmentInput>? attachments = null,
        CancellationToken cancellationToken = default)
    {
        var combined = string.Join(" / ", sourceTexts);
        var attachmentNote = attachments is { Count: > 0 } ? $"（添付{attachments.Count}件を含む）" : "";
        var draft = new PersonCardDraft(
            Summary: $"（ダミー要約）{fullName}氏。{(combined.Length > 0 ? $"入力情報より生成。{attachmentNote}" : "情報が少ないため簡易的な要約です。")}",
            Business: combined.Length > 0 ? "（ダミー）詳細は入力情報を確認してください。" : null,
            Issues: null,
            IntroducerName: null,
            Hobby: null);

        return Task.FromResult(draft);
    }

    public Task<string> ComposeTextAsync(
        string systemPrompt,
        string userPrompt,
        IReadOnlyCollection<AttachmentInput>? attachments = null,
        CancellationToken cancellationToken = default)
    {
        var attachmentNote = attachments is { Count: > 0 } ? $"（添付{attachments.Count}件を含む）" : "";
        return Task.FromResult($"（ダミー応答）LLMが未接続のため、検索結果の生データのみ確認してください。{attachmentNote}");
    }
}
