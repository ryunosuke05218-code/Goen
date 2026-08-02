namespace Goen.Domain.Entities;

public class Organization
{
    public Guid OrgId { get; set; }
    public string OrgName { get; set; } = null!;
    public Guid? ParentOrgId { get; set; }
    public string PlanType { get; set; } = "personal"; // personal / team / enterprise

    public DateTimeOffset CreatedAt { get; set; }
    public Guid? CreatedBy { get; set; }
    public DateTimeOffset UpdatedAt { get; set; }
    public Guid? UpdatedBy { get; set; }
    public int Version { get; set; }

    public ICollection<User> Users { get; set; } = new List<User>();
}
