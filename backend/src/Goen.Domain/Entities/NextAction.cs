namespace Goen.Domain.Entities;

public class NextAction
{
    public Guid ActionId { get; set; }
    public Guid PersonId { get; set; }
    public Guid UserId { get; set; }
    public string Content { get; set; } = null!;
    public DateOnly? DueDate { get; set; }
    public string Status { get; set; } = "open"; // open / done / canceled
    public DateTimeOffset? CompletedAt { get; set; }
    public Guid? SourceContactId { get; set; }

    public DateTimeOffset CreatedAt { get; set; }
    public Guid? CreatedBy { get; set; }
    public DateTimeOffset UpdatedAt { get; set; }
    public Guid? UpdatedBy { get; set; }
    public int Version { get; set; }

    public Person Person { get; set; } = null!;
}
