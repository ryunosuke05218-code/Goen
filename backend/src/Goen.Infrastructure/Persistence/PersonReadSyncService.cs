using System.Text.Json;
using Goen.Domain.Entities;
using Microsoft.EntityFrameworkCore;

namespace Goen.Infrastructure.Persistence;

// persons_read（参照最適化テーブル）をアプリケーション層から同期する。
// テーブル設計書 5.1 / D-005: トリガ同期か非同期キューかは未決のため、
// 本スキャフォールドでは書き込み経路の直後に同期再構築する最も単純な方式を採用する。
public class PersonReadSyncService
{
    private readonly GoenDbContext _db;

    public PersonReadSyncService(GoenDbContext db)
    {
        _db = db;
    }

    public async Task RefreshAsync(Guid personId, CancellationToken ct = default)
    {
        var person = await _db.Persons
            .Include(p => p.Company)
            .Include(p => p.Profile)
            .FirstOrDefaultAsync(p => p.PersonId == personId, ct);

        if (person is null)
        {
            await _db.PersonsRead.Where(r => r.PersonId == personId).ExecuteDeleteAsync(ct);
            return;
        }

        var latestCard = await _db.AiPersonCards
            .Where(c => c.PersonId == personId && c.IsLatest)
            .FirstOrDefaultAsync(ct);

        var contactCount = await _db.Contacts.CountAsync(c => c.PersonId == personId, ct);

        var openAction = await _db.NextActions
            .Where(a => a.PersonId == personId && a.Status == "open")
            .OrderBy(a => a.DueDate)
            .FirstOrDefaultAsync(ct);

        var searchText = string.Join(" ", new[]
        {
            person.FullName, person.FullNameKana, person.Company?.CompanyName,
            latestCard?.Summary, latestCard?.Issues, latestCard?.Business,
        }.Where(s => !string.IsNullOrWhiteSpace(s)));

        var read = await _db.PersonsRead.FirstOrDefaultAsync(r => r.PersonId == personId, ct);
        if (read is null)
        {
            read = new PersonRead { PersonId = personId };
            _db.PersonsRead.Add(read);
        }

        read.OrgId = person.OrgId;
        read.OwnerUserId = person.OwnerUserId;
        read.Visibility = person.Visibility;
        read.FullName = person.FullName;
        read.FullNameKana = person.FullNameKana;
        read.CompanyName = person.Company?.CompanyName;
        read.JobTitle = person.JobTitle;
        read.Importance = person.Importance;
        read.Summary = latestCard?.Summary;
        read.Issues = latestCard?.Issues;
        read.LastContactAt = person.LastContactAt;
        read.ContactCount = contactCount;
        read.OpenActionJson = openAction is null
            ? null
            : JsonSerializer.Serialize(new { content = openAction.Content, dueDate = openAction.DueDate });
        read.SearchText = searchText;
        read.RefreshedAt = DateTimeOffset.UtcNow;

        await _db.SaveChangesAsync(ct);
    }
}
