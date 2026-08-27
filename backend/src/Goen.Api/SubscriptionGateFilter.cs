using Goen.Infrastructure.Persistence;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Filters;
using Microsoft.EntityFrameworkCore;

namespace Goen.Api;

// サブスク課金: 有効な契約（active）または有効期限内のトライアル（trialing）でない組織は、
// 認証・課金関連（[AllowInactiveSubscription]を付与したコントローラ）以外のAPIを利用できないようにする。
// 「Web完結・アプリはログインのみ」という方針上、モバイルアプリ内には契約導線を置かないため、
// 実際の利用可否はこのサーバー側のゲートだけが唯一のよりどころになる。
public class SubscriptionGateFilter : IAsyncActionFilter
{
    private readonly GoenDbContext _db;

    public SubscriptionGateFilter(GoenDbContext db)
    {
        _db = db;
    }

    public async Task OnActionExecutionAsync(ActionExecutingContext context, ActionExecutionDelegate next)
    {
        var endpoint = context.HttpContext.GetEndpoint();
        if (endpoint?.Metadata.GetMetadata<AllowInactiveSubscriptionAttribute>() is not null)
        {
            await next();
            return;
        }

        // 未認証のリクエストは[Authorize]側の責務のため、ここでは素通りさせる。
        if (context.HttpContext.User.Identity?.IsAuthenticated != true)
        {
            await next();
            return;
        }

        Guid orgId;
        try
        {
            orgId = context.HttpContext.User.GetOrgId();
        }
        catch (InvalidOperationException)
        {
            await next();
            return;
        }

        var org = await _db.Organizations.AsNoTracking()
            .Where(o => o.OrgId == orgId)
            .Select(o => new { o.SubscriptionStatus, o.SubscriptionCurrentPeriodEnd, o.TrialEndsAt })
            .FirstOrDefaultAsync(context.HttpContext.RequestAborted);

        var now = DateTimeOffset.UtcNow;
        var isActive = org?.SubscriptionStatus == "active"
            && (org.SubscriptionCurrentPeriodEnd is null || org.SubscriptionCurrentPeriodEnd > now);
        var isTrialing = org?.SubscriptionStatus == "trialing"
            && org.TrialEndsAt is { } trialEnd && trialEnd > now;

        if (org is null || !(isActive || isTrialing))
        {
            context.Result = new ObjectResult(new
            {
                message = "ご利用にはサブスクリプションのご契約（更新）が必要です。",
                subscriptionStatus = org?.SubscriptionStatus,
            })
            {
                StatusCode = StatusCodes.Status402PaymentRequired,
            };
            return;
        }

        await next();
    }
}
