namespace Goen.Domain.Entities;

public class Company
{
    public Guid CompanyId { get; set; }
    public string CompanyName { get; set; } = null!;
    public string? CompanyNameKana { get; set; }
    public string CompanyNameNormalized { get; set; } = null!;
    public string? IndustryCode { get; set; }
    public string? PrefCode { get; set; }
    public string? Address { get; set; }
    public string? Url { get; set; }
    public string? EmployeeScale { get; set; }

    public DateTimeOffset CreatedAt { get; set; }
    public Guid? CreatedBy { get; set; }
    public DateTimeOffset UpdatedAt { get; set; }
    public Guid? UpdatedBy { get; set; }
    public int Version { get; set; }
}
