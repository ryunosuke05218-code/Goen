namespace Goen.Domain.Entities;

public class ContactMedia
{
    public Guid MediaId { get; set; }
    public Guid ContactId { get; set; }
    public string MediaType { get; set; } = "audio"; // business_card / audio / image / document
    public string StoragePath { get; set; } = null!;
    public long FileSize { get; set; }
    public int? DurationSec { get; set; }
    public decimal? OcrConfidence { get; set; }
    public string? OcrRawJson { get; set; }
    public string UploadStatus { get; set; } = "pending"; // pending / uploaded / failed

    public DateTimeOffset CreatedAt { get; set; }
    public Guid? CreatedBy { get; set; }
    public DateTimeOffset UpdatedAt { get; set; }
    public Guid? UpdatedBy { get; set; }
    public int Version { get; set; }

    public Contact Contact { get; set; } = null!;
}
