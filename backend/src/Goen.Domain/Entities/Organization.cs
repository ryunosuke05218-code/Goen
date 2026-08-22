namespace Goen.Domain.Entities;

public class Organization
{
    public Guid OrgId { get; set; }
    public string OrgName { get; set; } = null!;
    public Guid? ParentOrgId { get; set; }
    public string PlanType { get; set; } = "personal"; // personal / team / enterprise

    public string SubscriptionStatus { get; set; } = "trialing"; // trialing / active / past_due / canceled / incomplete
    public string? SubscriptionProvider { get; set; } // stripe / google_play / app_store
    public string? SubscriptionPlanCode { get; set; }
    public string? SubscriptionProviderCustomerId { get; set; }
    public string? SubscriptionProviderSubscriptionId { get; set; }
    public DateTimeOffset? SubscriptionCurrentPeriodEnd { get; set; }
    public DateTimeOffset? TrialEndsAt { get; set; }

    public DateTimeOffset CreatedAt { get; set; }
    public Guid? CreatedBy { get; set; }
    public DateTimeOffset UpdatedAt { get; set; }
    public Guid? UpdatedBy { get; set; }
    public int Version { get; set; }

    public ICollection<User> Users { get; set; } = new List<User>();
}
