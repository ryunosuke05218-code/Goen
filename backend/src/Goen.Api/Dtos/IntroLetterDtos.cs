namespace Goen.Api.Dtos;

// F-026 紹介文（例文）作成: 対象人物・要件・その他条件、任意のHPリンク・資料ファイルから、AIがその人物向けの文面を1件作成する。
// 資料ファイル（IFormFile）を扱うためmultipart/form-dataで受け取る（[FromForm]の個別パラメータでバインドする。
// PersonsController.GenerateCardと同じ方式）。

public record GenerateIntroLetterResponse(string Message);

public record IntroLetterHistoryItemResponse(
    Guid RequestId,
    Guid TargetPersonId,
    string TargetPersonName,
    string Requirement,
    string? Tone,
    string? LengthHint,
    string? AdditionalNotes,
    string? HpUrl,
    string? AttachedFileName,
    string GeneratedMessage,
    DateTimeOffset CreatedAt);
