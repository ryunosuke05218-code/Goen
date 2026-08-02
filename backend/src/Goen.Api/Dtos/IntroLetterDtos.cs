namespace Goen.Api.Dtos;

// F-026 紹介文（例文）作成: 対象人物・要件・その他条件から、AIがその人物向けの文面を1件作成する
public record GenerateIntroLetterRequest(
    Guid TargetPersonId,
    string Requirement,
    string? Tone,
    string? LengthHint,
    string? AdditionalNotes);

public record GenerateIntroLetterResponse(string Message);
