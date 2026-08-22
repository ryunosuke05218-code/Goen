using Goen.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using Stripe;
using Stripe.Checkout;

namespace Goen.Infrastructure.Billing;

// サブスク課金（Stripe実装）。Stripe Checkout（ホスト型決済ページ）とカスタマーポータルへの
// 遷移URLを発行するのみで、実際の課金状態の更新はWebhook（StripeWebhookController）が担う
// （Checkout完了は非同期にWebhookで通知されるため、CreateCheckoutSessionAsync自体は組織の状態を変更しない）。
public class StripeSubscriptionService : ISubscriptionService
{
    private readonly GoenDbContext _db;
    private readonly SubscriptionOptions _options;
    private readonly StripeClient _client;

    public StripeSubscriptionService(GoenDbContext db, IOptions<SubscriptionOptions> options)
    {
        _db = db;
        _options = options.Value;
        _client = new StripeClient(_options.ApiKey);
    }

    public async Task<SubscriptionStatus> GetStatusAsync(Guid orgId, CancellationToken cancellationToken = default)
    {
        var org = await _db.Organizations.FirstOrDefaultAsync(o => o.OrgId == orgId, cancellationToken)
            ?? throw new InvalidOperationException("組織が見つかりません。");
        return new SubscriptionStatus(
            org.SubscriptionStatus, org.SubscriptionProvider, org.SubscriptionPlanCode,
            org.SubscriptionCurrentPeriodEnd, org.TrialEndsAt);
    }

    public async Task<CheckoutSession> CreateCheckoutSessionAsync(Guid orgId, string planCode, CancellationToken cancellationToken = default)
    {
        if (!_options.PlanPriceIds.TryGetValue(planCode, out var priceId))
        {
            throw new InvalidOperationException($"プランコード '{planCode}' に対応するStripe Price IDが設定されていません。");
        }

        var org = await _db.Organizations
            .Include(o => o.Users)
            .FirstOrDefaultAsync(o => o.OrgId == orgId, cancellationToken)
            ?? throw new InvalidOperationException("組織が見つかりません。");

        var customerId = org.SubscriptionProviderCustomerId;
        if (customerId is null)
        {
            var ownerEmail = org.Users.OrderBy(u => u.CreatedAt).FirstOrDefault()?.Email;
            var customerService = new CustomerService(_client);
            var customer = await customerService.CreateAsync(new CustomerCreateOptions
            {
                Email = ownerEmail,
                Metadata = new Dictionary<string, string> { ["org_id"] = orgId.ToString() },
            }, cancellationToken: cancellationToken);
            customerId = customer.Id;
            org.SubscriptionProviderCustomerId = customerId;
            await _db.SaveChangesAsync(cancellationToken);
        }

        var sessionService = new SessionService(_client);
        var session = await sessionService.CreateAsync(new SessionCreateOptions
        {
            Mode = "subscription",
            Customer = customerId,
            ClientReferenceId = orgId.ToString(),
            LineItems = new List<SessionLineItemOptions>
            {
                new() { Price = priceId, Quantity = 1 },
            },
            SuccessUrl = _options.SuccessUrl,
            CancelUrl = _options.CancelUrl,
            Metadata = new Dictionary<string, string> { ["org_id"] = orgId.ToString(), ["plan_code"] = planCode },
        }, cancellationToken: cancellationToken);

        return new CheckoutSession(session.Url);
    }

    public async Task<BillingPortalSession> CreateBillingPortalSessionAsync(Guid orgId, CancellationToken cancellationToken = default)
    {
        var org = await _db.Organizations.FirstOrDefaultAsync(o => o.OrgId == orgId, cancellationToken)
            ?? throw new InvalidOperationException("組織が見つかりません。");
        if (org.SubscriptionProviderCustomerId is null)
        {
            throw new InvalidOperationException("まだ契約情報がありません。先にプランへ加入してください。");
        }

        var portalService = new Stripe.BillingPortal.SessionService(_client);
        var session = await portalService.CreateAsync(new Stripe.BillingPortal.SessionCreateOptions
        {
            Customer = org.SubscriptionProviderCustomerId,
            ReturnUrl = _options.PortalReturnUrl,
        }, cancellationToken: cancellationToken);

        return new BillingPortalSession(session.Url);
    }
}
