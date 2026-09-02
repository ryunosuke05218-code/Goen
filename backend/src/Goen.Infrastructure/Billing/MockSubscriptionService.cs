using Goen.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace Goen.Infrastructure.Billing;

// 決済プロバイダ（Stripe等）未接続の開発環境向けダミー実装。実際の決済は行わず、
// チェックアウトを即座に「成功」として組織の契約状態を更新する（ブラウザ遷移や外部APIが不要なため、
// アプリ側の契約状態表示・分岐のUI確認をAPIキー無しで行える）。
public class MockSubscriptionService : ISubscriptionService
{
    private readonly GoenDbContext _db;

    public MockSubscriptionService(GoenDbContext db)
    {
        _db = db;
    }

    public async Task<SubscriptionStatus> GetStatusAsync(Guid orgId, CancellationToken cancellationToken = default)
    {
        var org = await _db.Organizations.FirstOrDefaultAsync(o => o.OrgId == orgId, cancellationToken)
            ?? throw new InvalidOperationException("組織が見つかりません。");
        return ToStatus(org);
    }

    public async Task<CheckoutSession> CreateCheckoutSessionAsync(Guid orgId, string planCode, CancellationToken cancellationToken = default)
    {
        var org = await _db.Organizations.FirstOrDefaultAsync(o => o.OrgId == orgId, cancellationToken)
            ?? throw new InvalidOperationException("組織が見つかりません。");

        org.SubscriptionStatus = "active";
        org.SubscriptionProvider = "stripe";
        org.SubscriptionPlanCode = planCode;
        org.SubscriptionProviderCustomerId ??= $"mock-customer-{org.OrgId}";
        org.SubscriptionProviderSubscriptionId = $"mock-subscription-{Guid.NewGuid()}";
        org.SubscriptionCurrentPeriodEnd = DateTimeOffset.UtcNow.AddDays(30);
        await _db.SaveChangesAsync(cancellationToken);

        // URLを空文字にすることで、モバイル側は「ブラウザを開かず契約が完了した」ことを示す
        // モック環境向けの分岐として扱う（決済プロバイダ未接続でもUI確認ができるようにするため）。
        return new CheckoutSession("");
    }

    public Task<BillingPortalSession> CreateBillingPortalSessionAsync(Guid orgId, CancellationToken cancellationToken = default)
        => Task.FromResult(new BillingPortalSession(""));

    public async Task CancelSubscriptionAsync(Guid orgId, CancellationToken cancellationToken = default)
    {
        var org = await _db.Organizations.FirstOrDefaultAsync(o => o.OrgId == orgId, cancellationToken)
            ?? throw new InvalidOperationException("組織が見つかりません。");
        org.SubscriptionStatus = "canceled";
        await _db.SaveChangesAsync(cancellationToken);
    }

    private static SubscriptionStatus ToStatus(Domain.Entities.Organization org) => new(
        org.SubscriptionStatus, org.SubscriptionProvider, org.SubscriptionPlanCode,
        org.SubscriptionCurrentPeriodEnd, org.TrialEndsAt);
}
