namespace Goen.Domain.Entities;

public class Transcript
{
    public Guid TranscriptId { get; set; }
    public Guid ContactId { get; set; }
    public Guid? MediaId { get; set; }
    public string Content { get; set; } = null!;
    public bool ContentEdited { get; set; }
    public decimal? Confidence { get; set; }
    public string AsrModel { get; set; } = null!;
    public string Language { get; set; } = "ja";
    public string Status { get; set; } = "processing"; // processing / done / failed

    public DateTimeOffset CreatedAt { get; set; }
    public Guid? CreatedBy { get; set; }
    public DateTimeOffset UpdatedAt { get; set; }
    public Guid? UpdatedBy { get; set; }
    public int Version { get; set; }

    public Contact Contact { get; set; } = null!;
}
