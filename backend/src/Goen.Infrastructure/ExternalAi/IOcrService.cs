namespace Goen.Infrastructure.ExternalAi;

// F-007 名刺データOCR読み込み機能（I-001）
public record OcrResult(
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

public interface IOcrService
{
    Task<OcrResult> ExtractAsync(Stream imageStream, CancellationToken cancellationToken = default);
}
