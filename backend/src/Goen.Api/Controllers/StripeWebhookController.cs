using Goen.Infrastructure.Persistence;
using Goen.Infrastructure.Billing;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using Stripe;

namespace Goen.Api.Controllers;

// Stripeからのサブスク状態変更通知（Webhook）。JWT認証は使わず、Stripe-Signatureヘッダの
// 署名検証（EventUtility.ConstructEvent）で正当な送信元であることを確認する。
// Checkout完了は非同期にここで通知されるため、実際に組織の契約状態（organizations.subscription_*）を
// 更新するのは本コントローラの役割であり、BillingController.CreateCheckoutは遷移URLの発行のみ行う。
[ApiController]
[AllowAnonymous]
[Route("api/billing/webhook")]
public class StripeWebhookController : ControllerBase
{
    private readonly GoenDbContext _db;
    private readonly SubscriptionOptions _options;
    private readonly ILogger<StripeWebhookController> _logger;

    public StripeWebhookController(GoenDbContext db, IOptions<SubscriptionOptions> options, ILogger<StripeWebhookController> logger)
    {
        _db = db;
        _options = options.Value;
        _logger = logger;
    }

    [HttpPost]
    public async Task<IActionResult> Handle(CancellationToken ct)
    {
        var json = await new StreamReader(Request.Body).ReadToEndAsync(ct);

        Event stripeEvent;
        try
        {
            stripeEvent = EventUtility.ConstructEvent(json, Request.Headers["Stripe-Signature"], _options.WebhookSecret);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Stripe Webhookの署名検証に失敗しました");
            return BadRequest();
        }

        switch (stripeEvent.Type)
        {
            case "checkout.session.completed":
            {
                var session = (Stripe.Checkout.Session)stripeEvent.Data.Object;
                if (Guid.TryParse(session.ClientReferenceId ?? session.Metadata?.GetValueOrDefault("org_id"), out var orgId))
                {
                    var org = await _db.Organizations.FirstOrDefaultAsync(o => o.OrgId == orgId, ct);
                    if (org is not null)
                    {
                        org.SubscriptionProvider = "stripe";
                        org.SubscriptionProviderCustomerId = session.CustomerId;
                        org.SubscriptionProviderSubscriptionId = session.SubscriptionId;
                        if (session.Metadata?.TryGetValue("plan_code", out var planCode) == true)
                        {
                            org.SubscriptionPlanCode = planCode;
                        }
                        org.SubscriptionStatus = "active";
                        await _db.SaveChangesAsync(ct);
                    }
                }
                break;
            }
            case "customer.subscription.updated":
            case "customer.subscription.created":
            {
                var subscription = (Subscription)stripeEvent.Data.Object;
                var org = await _db.Organizations
                    .FirstOrDefaultAsync(o => o.SubscriptionProviderSubscriptionId == subscription.Id
                        || o.SubscriptionProviderCustomerId == subscription.CustomerId, ct);
                if (org is not null)
                {
                    org.SubscriptionProviderSubscriptionId = subscription.Id;
                    org.SubscriptionStatus = MapStripeStatus(subscription.Status);
                    org.SubscriptionCurrentPeriodEnd = subscription.CurrentPeriodEnd;
                    await _db.SaveChangesAsync(ct);
                }
                break;
            }
            case "customer.subscription.deleted":
            {
                var subscription = (Subscription)stripeEvent.Data.Object;
                var org = await _db.Organizations
                    .FirstOrDefaultAsync(o => o.SubscriptionProviderSubscriptionId == subscription.Id, ct);
                if (org is not null)
                {
                    org.SubscriptionStatus = "canceled";
                    await _db.SaveChangesAsync(ct);
                }
                break;
            }
        }

        return Ok();
    }

    private static string MapStripeStatus(string stripeStatus) => stripeStatus switch
    {
        "trialing" => "trialing",
        "active" => "active",
        "past_due" => "past_due",
        "canceled" => "canceled",
        "incomplete_expired" => "canceled",
        "unpaid" => "past_due",
        _ => "incomplete",
    };
}
