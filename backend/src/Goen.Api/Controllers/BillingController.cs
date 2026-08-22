using Goen.Api.Dtos;
using Goen.Infrastructure.Billing;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Goen.Api.Controllers;

// サブスク課金。決済プロバイダはStripeを想定して実装するが、App Store/Google Play配布時は
// ストアのIAP（アプリ内課金）使用が規約上必須になるため、ISubscriptionServiceの実装差し替えのみで
// 対応できるよう設計している（本コントローラのコード自体は変更不要な想定）。
[ApiController]
[Authorize]
[Route("api/billing")]
public class BillingController : ControllerBase
{
    private readonly ISubscriptionService _subscription;

    public BillingController(ISubscriptionService subscription)
    {
        _subscription = subscription;
    }

    [HttpGet("subscription")]
    public async Task<ActionResult<SubscriptionStatusResponse>> GetSubscription(CancellationToken ct)
    {
        var status = await _subscription.GetStatusAsync(User.GetOrgId(), ct);
        return Ok(new SubscriptionStatusResponse(status.Status, status.Provider, status.PlanCode, status.CurrentPeriodEnd, status.TrialEndsAt));
    }

    [HttpPost("checkout")]
    public async Task<ActionResult<CheckoutSessionResponse>> CreateCheckout(CreateCheckoutRequest request, CancellationToken ct)
    {
        try
        {
            var session = await _subscription.CreateCheckoutSessionAsync(User.GetOrgId(), request.PlanCode, ct);
            return Ok(new CheckoutSessionResponse(session.Url));
        }
        catch (InvalidOperationException ex)
        {
            return BadRequest(new { message = ex.Message });
        }
    }

    [HttpPost("portal")]
    public async Task<ActionResult<BillingPortalSessionResponse>> CreatePortal(CancellationToken ct)
    {
        try
        {
            var session = await _subscription.CreateBillingPortalSessionAsync(User.GetOrgId(), ct);
            return Ok(new BillingPortalSessionResponse(session.Url));
        }
        catch (InvalidOperationException ex)
        {
            return BadRequest(new { message = ex.Message });
        }
    }
}
