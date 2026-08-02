namespace Goen.Domain.Entities;

public class User
{
    public Guid UserId { get; set; }
    public Guid OrgId { get; set; }
    public string Email { get; set; } = null!;
    public string PasswordHash { get; set; } = null!;
    public string DisplayName { get; set; } = null!;
    public string Role { get; set; } = "member"; // member / manager / org_admin / sys_admin
    public string Status { get; set; } = "active"; // active / suspended / retired
    public DateTimeOffset? LastLoginAt { get; set; }

    public DateTimeOffset CreatedAt { get; set; }
    public Guid? CreatedBy { get; set; }
    public DateTimeOffset UpdatedAt { get; set; }
    public Guid? UpdatedBy { get; set; }
    public int Version { get; set; }

    public Organization Organization { get; set; } = null!;
}
