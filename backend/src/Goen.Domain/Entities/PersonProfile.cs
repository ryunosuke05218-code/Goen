namespace Goen.Domain.Entities;

public class PersonProfile
{
    public Guid PersonId { get; set; }
    public string? Tel { get; set; }
    public string? Mobile { get; set; }
    public string? Email { get; set; }
    public string? PrefCode { get; set; }
    public string? Address { get; set; }
    public string? Url { get; set; }
    public string SnsAccountsJson { get; set; } = "{}";
    public DateOnly? Birthday { get; set; }
    public string? Note { get; set; }

    public DateTimeOffset CreatedAt { get; set; }
    public Guid? CreatedBy { get; set; }
    public DateTimeOffset UpdatedAt { get; set; }
    public Guid? UpdatedBy { get; set; }
    public int Version { get; set; }

    public Person Person { get; set; } = null!;
}
