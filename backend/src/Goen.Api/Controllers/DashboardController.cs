using Goen.Api.Dtos;
using Goen.Infrastructure.Persistence;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace Goen.Api.Controllers;

// F-029 ダッシュボード: 自分の人脈の総人数・業種別/職種別の内訳・近い接点予定を一覧表示する。
// persons_read（参照最適化テーブル）を集計するだけなので、AIは使用しない。
[ApiController]
[Authorize]
[Route("api/dashboard")]
public class DashboardController : ControllerBase
{
    private readonly GoenDbContext _db;

    public DashboardController(GoenDbContext db)
    {
        _db = db;
    }

    [HttpGet]
    public async Task<ActionResult<DashboardResponse>> Get(CancellationToken ct)
    {
        var userId = User.GetUserId();
        var orgId = User.GetOrgId();

        var persons = _db.PersonsRead.Where(r => r.OwnerUserId == userId && r.OrgId == orgId);

        var totalCount = await persons.CountAsync(ct);

        var industryGroups = await persons
            .GroupBy(r => r.IndustryName)
            .Select(g => new { Name = g.Key, Count = g.Count() })
            .ToListAsync(ct);
        var industryBreakdown = industryGroups
            .Select(x => new IndustryCountItem(x.Name ?? "業種未設定", x.Count))
            .OrderByDescending(x => x.Count)
            .ToList();

        var occupationGroups = await persons
            .GroupBy(r => r.OccupationName)
            .Select(g => new { Name = g.Key, Count = g.Count() })
            .ToListAsync(ct);
        var occupationBreakdown = occupationGroups
            .Select(x => new OccupationCountItem(x.Name ?? "職種未設定", x.Count))
            .OrderByDescending(x => x.Count)
            .ToList();

        var upcomingContacts = await _db.NextActions
            .Where(a => a.Status == "open" && a.DueDate != null)
            .Join(persons, a => a.PersonId, r => r.PersonId, (a, r) => new { Action = a, Person = r })
            .OrderBy(x => x.Action.DueDate)
            .Take(5)
            .Select(x => new UpcomingContactItem(x.Person.PersonId, x.Person.FullName, x.Action.Content, x.Action.DueDate))
            .ToListAsync(ct);

        return Ok(new DashboardResponse(totalCount, industryBreakdown, occupationBreakdown, upcomingContacts));
    }
}
