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

        // 自分自身の人物カルテ（is_self）は人脈の連絡先ではないため、集計対象から除外する
        var persons = _db.PersonsRead.Where(r => r.OwnerUserId == userId && r.OrgId == orgId && !r.IsSelf);

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

        // 「近い接点予定」＝今日から1週間以内に予定されている接点記録（Contacts.OccurredAtが未来日のもの）。
        // 接点記録画面の日付選択では過去だけでなく最大365日先までの未来日も選べるため、
        // 今後の予定として登録された接点をそのままここに反映する。
        var todayStart = new DateTimeOffset(DateTime.UtcNow.Date, TimeSpan.Zero);
        var rangeEnd = todayStart.AddDays(7);
        var upcomingContacts = await _db.Contacts
            .Where(c => c.OccurredAt >= todayStart && c.OccurredAt <= rangeEnd)
            .Join(persons, c => c.PersonId, r => r.PersonId, (c, r) => new { Contact = c, Person = r })
            .OrderBy(x => x.Contact.OccurredAt)
            .Take(20)
            .Select(x => new UpcomingContactItem(x.Person.PersonId, x.Person.FullName, x.Contact.ContactType, x.Contact.OccurredAt, x.Contact.Place))
            .ToListAsync(ct);

        return Ok(new DashboardResponse(totalCount, industryBreakdown, occupationBreakdown, upcomingContacts));
    }
}
