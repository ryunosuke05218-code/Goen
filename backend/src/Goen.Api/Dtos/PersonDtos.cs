namespace Goen.Api.Dtos;

public record PersonListItem(
    Guid PersonId,
    string FullName,
    string? FullNameKana,
    string? CompanyName,
    string? JobTitle,
    short Importance,
    string? Summary,
    DateTimeOffset? LastContactAt,
    int ContactCount);

public record PersonDetail(
    Guid PersonId,
    string FullName,
    string? FullNameKana,
    string? Department,
    string? JobTitle,
    Guid? CompanyId,
    string? CompanyName,
    short Importance,
    bool ImportanceIsManual,
    string Visibility,
    DateOnly? FirstMetAt,
    DateTimeOffset? LastContactAt,
    string SourceType,
    string? Tel,
    string? Mobile,
    string? Email,
    string? Address,
    string? Note,
    string? AiSummary,
    string? AiBusiness,
    string? AiIssues,
    string? AiHobby,
    Guid? IntroducerPersonId,
    string? IntroducerPersonName);

public record CreatePersonRequest(
    string FullName,
    string? FullNameKana,
    string? Department,
    string? JobTitle,
    string? CompanyName,
    string? Tel,
    string? Mobile,
    string? Email,
    string? Address,
    string? Note = null,
    string SourceType = "manual",
    Guid? IntroducerPersonId = null);

public record UpdatePersonRequest(
    string FullName,
    string? FullNameKana,
    string? Department,
    string? JobTitle,
    string? CompanyName,
    short Importance,
    bool ImportanceIsManual,
    string Visibility,
    string? Tel,
    string? Mobile,
    string? Email,
    string? Address,
    string? Note);

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
    decimal Confidence);

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
