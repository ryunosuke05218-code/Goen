namespace Goen.Infrastructure.ExternalAi;

// F-010 AI人物カルテ生成機能（I-003）
public record PersonCardDraft(
    string Summary,
    string? Business,
    string? Issues,
    string? IntroducerName,
    string? Hobby);

// F-010: AI人物カルテ生成時に任意で添付される画像・PDF等（テキスト抽出は行わず、LLMへそのまま渡す）
public record AttachmentInput(byte[] Bytes, string MimeType);

public interface ILlmService
{
    Task<PersonCardDraft> GeneratePersonCardAsync(
        string fullName,
        IReadOnlyCollection<string> sourceTexts,
        IReadOnlyCollection<AttachmentInput>? attachments = null,
        CancellationToken cancellationToken = default);

    // AIアシスタント（人脈経路提案・RAGヒント）・紹介文作成（F-026）の自然文回答生成に使用する汎用のテキスト生成メソッド。
    // JSON modeは使わず、systemPromptで出力形式を指示したうえで自由文を受け取る。
    // F-026: HPリンクの本文・資料ファイル（画像/PDF）を任意で添付できる（GeneratePersonCardAsyncと同じ添付の扱い）。
    Task<string> ComposeTextAsync(
        string systemPrompt,
        string userPrompt,
        IReadOnlyCollection<AttachmentInput>? attachments = null,
        CancellationToken cancellationToken = default);
}
