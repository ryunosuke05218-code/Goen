using Goen.Api.Dtos;
using Goen.Infrastructure.Persistence;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace Goen.Api.Controllers;

// 静的マスタの参照用（Q-011解消：職種マスタの選択肢取得に使用）
[ApiController]
[Authorize]
[Route("api/masters")]
public class MastersController : ControllerBase
{
    private readonly GoenDbContext _db;

    public MastersController(GoenDbContext db)
    {
        _db = db;
    }

    // F-006: 人物編集画面の職種選択肢、人脈図の階層グルーピングの元データ
    [HttpGet("occupation-types")]
    public async Task<ActionResult<IReadOnlyList<OccupationTypeItem>>> ListOccupationTypes(CancellationToken ct)
    {
        var items = await _db.OccupationTypes
            .Where(o => o.IsActive)
            .OrderBy(o => o.SortOrder)
            .Select(o => new OccupationTypeItem(o.OccupationCode, o.OccupationName))
            .ToListAsync(ct);

        return Ok(items);
    }
}
