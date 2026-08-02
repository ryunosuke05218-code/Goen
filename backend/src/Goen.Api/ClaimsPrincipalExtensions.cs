using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;

namespace Goen.Api;

public static class ClaimsPrincipalExtensions
{
    public static Guid GetUserId(this ClaimsPrincipal user) =>
        Guid.Parse(user.FindFirstValue(JwtRegisteredClaimNames.Sub)
            ?? throw new InvalidOperationException("トークンに sub クレームがありません。"));

    public static Guid GetOrgId(this ClaimsPrincipal user) =>
        Guid.Parse(user.FindFirstValue("org_id")
            ?? throw new InvalidOperationException("トークンに org_id クレームがありません。"));
}
