using Goen.Api.Dtos;
using Goen.Infrastructure.Persistence;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace Goen.Api.Controllers;

// ログイン中ユーザー自身の設定（F-028 相互人脈登録のON/OFF等）
[ApiController]
[Authorize]
[Route("api/users")]
public class UsersController : ControllerBase
{
    private readonly GoenDbContext _db;

    public UsersController(GoenDbContext db)
    {
        _db = db;
    }

    // F-027: 他ユーザーの人脈図（業種階層まで）を見る際の選択肢として、同一組織のメンバー一覧を返す
    [HttpGet]
    public async Task<ActionResult<IReadOnlyList<OrgMemberItem>>> ListOrgMembers(CancellationToken ct)
    {
        var orgId = User.GetOrgId();
        var members = await _db.Users
            .Where(u => u.OrgId == orgId && u.UserId != User.GetUserId() && u.Status == "active")
            .OrderBy(u => u.DisplayName)
            .Select(u => new OrgMemberItem(u.UserId, u.DisplayName))
            .ToListAsync(ct);

        return Ok(members);
    }

    [HttpGet("me")]
    public async Task<ActionResult<UserSettingsResponse>> GetMe(CancellationToken ct)
    {
        var user = await _db.Users.FirstOrDefaultAsync(u => u.UserId == User.GetUserId(), ct);
        if (user is null) return NotFound();

        return Ok(new UserSettingsResponse(user.UserId, user.Email, user.DisplayName, user.AllowMutualRegistration));
    }

    [HttpPut("me/settings")]
    public async Task<ActionResult<UserSettingsResponse>> UpdateSettings(UpdateUserSettingsRequest request, CancellationToken ct)
    {
        var user = await _db.Users.FirstOrDefaultAsync(u => u.UserId == User.GetUserId(), ct);
        if (user is null) return NotFound();

        user.AllowMutualRegistration = request.AllowMutualRegistration;
        user.UpdatedBy = User.GetUserId();
        await _db.SaveChangesAsync(ct);

        return Ok(new UserSettingsResponse(user.UserId, user.Email, user.DisplayName, user.AllowMutualRegistration));
    }
}
