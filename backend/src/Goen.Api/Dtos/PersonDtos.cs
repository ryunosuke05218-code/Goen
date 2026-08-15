namespace Goen.Api.Dtos;

// SNSリンク（何個でも追加可能）。名刺のQRコードから読み取った場合はLabelを自動推定して返す（F-007）
public record SnsLink(string? Label, string Url);

public record PersonListItem(
    Guid PersonId,
    string FullName,
    string? FullNameKana,
    string? CompanyName,
    string? JobTitle,
    string? Summary,
    DateTimeOffset? LastContactAt,
    int ContactCount);

// F-003: 一覧の総登録人数を併せて返す
public record PersonListResponse(IReadOnlyList<PersonListItem> Items, int TotalCount);

public record PersonDetail(
    Guid PersonId,
    string FullName,
    string? FullNameKana,
    string? Department,
    string? JobTitle,
    string? OccupationCode,
    string? OccupationName,
    string? IndustryName,
    Guid? CompanyId,
    string? CompanyName,
    string Visibility,
    DateOnly? FirstMetAt,
    string? MetPlace,
    DateTimeOffset? LastContactAt,
    string SourceType,
    string? Tel,
    string? Mobile,
    string? Email,
    string? Address,
    string? Note,
    IReadOnlyList<SnsLink> SnsLinks,
    string? AiSummary,
    string? AiBusiness,
    string? AiIssues,
    string? AiHobby,
    Guid? IntroducerPersonId,
    string? IntroducerPersonName,
    // F-032: AI要約の参照元表示。生成時に参照したHPリンク・資料ファイル・接点メモ件数
    IReadOnlyList<string> AiSummarySourceUrls,
    IReadOnlyList<string> AiSummarySourceFiles,
    int AiSummaryContactCount);

public record CreatePersonRequest(
    string FullName,
    string? FullNameKana,
    string? Department,
    string? JobTitle,
    string? OccupationName,
    string? IndustryName,
    string? CompanyName,
    string? Tel,
    string? Mobile,
    string? Email,
    string? Address,
    string? Note = null,
    string? MetPlace = null,
    IReadOnlyList<SnsLink>? SnsLinks = null,
    string SourceType = "manual",
    Guid? IntroducerPersonId = null);

public record UpdatePersonRequest(
    string FullName,
    string? FullNameKana,
    string? Department,
    string? JobTitle,
    string? OccupationName,
    string? IndustryName,
    string? CompanyName,
    string Visibility,
    string? Tel,
    string? Mobile,
    string? Email,
    string? Address,
    string? Note,
    string? MetPlace,
    IReadOnlyList<SnsLink>? SnsLinks);

public record OcrDraftResponse(
    string? FullName,
    string? FullNameKana,
    string? CompanyName,
    string? Department,
    string? JobTitle,
    string? Tel,
    string? Mobile,
    string? Email,
    string? Address,
    string? Url,
    decimal Confidence,
    IReadOnlyList<SnsLink> SnsLinks);

// F-007: 名刺OCR結果（フォームの現在値）と音声文字起こしをAIで統合する
public record RefineOcrDraftRequest(
    string? FullName,
    string? FullNameKana,
    string? CompanyName,
    string? Department,
    string? JobTitle,
    string? Tel,
    string? Mobile,
    string? Email,
    string? Address,
    string VoiceText);

// F-002: 手入力登録画面での音声メモをAIが解析し、各登録項目に振り分ける
public record VoiceDraftRequest(string VoiceText);

public record VoiceDraftResponse(
    string? FullName,
    string? FullNameKana,
    string? CompanyName,
    string? JobTitle,
    string? Email,
    string? Mobile,
    string? Note,
    string? MetPlace);

public record CreateContactRequest(
    string ContactType,
    DateTimeOffset OccurredAt,
    string? Place,
    string? Note);

public record UpdateContactNoteRequest(string? Note);

public record ContactItem(
    Guid ContactId,
    string ContactType,
    DateTimeOffset OccurredAt,
    string? Place,
    string? Note,
    bool HasMedia);

public record VoiceMemoResponse(string TranscriptText, decimal Confidence);

public record GenerateCardResponse(string Summary, string? Business, string? Issues, string? Hobby, int Generation);
