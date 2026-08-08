using Goen.Api.Dtos;
using Goen.Infrastructure.Persistence;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace Goen.Api.Controllers;

// F-005/F-006 人脈グラフ（自分を中心としたマインドマップ）
[ApiController]
[Authorize]
[Route("api/network")]
public class NetworkController : ControllerBase
{
    private readonly GoenDbContext _db;
    private readonly NetworkGraphService _network;

    public NetworkController(GoenDbContext db, NetworkGraphService network)
    {
        _db = db;
        _network = network;
    }

    // 自分（ログインユーザー）を中心に、直接の人脈(depth1)とその先の二次接点(depth2)を返す。
    // F-006: ノードには業種名・職種名を含めており、階層ツリーへのグルーピングはクライアント側で行う
    // （基本設計書7.4節: データモデル（ノード＝人物、エッジ＝関係）自体は変更せず、レイアウトのみをツリー化する）。
    [HttpGet]
    public async Task<ActionResult<NetworkGraphResponse>> GetMyNetwork(
        [FromQuery] int depth1Limit, [FromQuery] int depth2Limit, CancellationToken ct)
    {
        var userId = User.GetUserId();
        var orgId = User.GetOrgId();

        var displayName = await _db.Users
            .Where(u => u.UserId == userId)
            .Select(u => u.DisplayName)
            .FirstOrDefaultAsync(ct) ?? "自分";

        var graph = await _network.GetMyNetworkAsync(
            userId, orgId, displayName,
            depth1Limit <= 0 ? 25 : depth1Limit,
            depth2Limit <= 0 ? 40 : depth2Limit,
            ct);

        return Ok(new NetworkGraphResponse(
            graph.Nodes.Select(n => new NetworkNodeResponse(n.PersonId, n.FullName, n.CompanyName, n.IndustryName, n.OccupationName, n.Importance, n.Depth, n.IsSelf)).ToList(),
            graph.Edges.Select(e => new NetworkEdgeResponse(e.RelationId, e.FromPersonId, e.ToPersonId, e.RelationType, e.Strength)).ToList()));
    }

    // F-027: 同一組織内の他ユーザーの人脈を、業種ごとの人数集計のみで返す（個々の人物・職種・会社名は含まない）
    [HttpGet("industry-summary")]
    public async Task<ActionResult<IndustryBreakdownResponse>> GetIndustrySummary([FromQuery] Guid userId, CancellationToken ct)
    {
        var orgId = User.GetOrgId();

        var target = await _db.Users
            .Where(u => u.UserId == userId && u.OrgId == orgId)
            .Select(u => new { u.UserId, u.DisplayName })
            .FirstOrDefaultAsync(ct);
        if (target is null) return NotFound();

        var breakdown = await _network.GetIndustryBreakdownAsync(userId, orgId, ct);
        var totalCount = breakdown.Sum(b => b.Count);

        return Ok(new IndustryBreakdownResponse(
            target.UserId, target.DisplayName, totalCount,
            breakdown.Select(b => new IndustryCountItem(b.IndustryName, b.Count)).ToList()));
    }
}
