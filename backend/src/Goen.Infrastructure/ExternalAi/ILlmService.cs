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

// F-005 人脈グラフ作成（AI推定）: LLMに候補者一覧を渡し、関係性を提案させる
public record PersonContext(
    Guid PersonId,
    string FullName,
    string? CompanyName,
    string? JobTitle,
    string? Summary,
    string? Issues,
    string? IntroducerName);

public record RelationSuggestion(
    Guid RelatedPersonId,
    string RelationType, // referrer（紹介元） / community（人脈・知人）
    string Reason,
    int Strength); // 1-5

public interface ILlmService
{
    Task<PersonCardDraft> GeneratePersonCardAsync(
        string fullName,
        IReadOnlyCollection<string> sourceTexts,
        IReadOnlyCollection<AttachmentInput>? attachments = null,
        CancellationToken cancellationToken = default);

    Task<IReadOnlyList<RelationSuggestion>> SuggestRelationsAsync(
        PersonContext target,
        IReadOnlyList<PersonContext> candidates,
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
