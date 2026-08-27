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
            .Include(p => p.Occupation)
            .FirstOrDefaultAsync(p => p.PersonId == personId, ct);

        if (person is null)
        {
            await _db.PersonsRead.Where(r => r.PersonId == personId).ExecuteDeleteAsync(ct);
            return;
        }

        // 業種は人物ごとに直接選択された値（F-030拡張、固定8種からのプルダウン選択）を優先する。
        // 職種は複数業種にまたがりうるため業種の導出元にはできない。会社のindustry_codeは入力経路がなく
        // 実質未設定のままのため、人物の業種が未設定の場合のみ補助的にフォールバックする。
        var industryCode = person.IndustryCode ?? person.Company?.IndustryCode;
        var industryName = industryCode is null
            ? null
            : await _db.Industries.Where(i => i.IndustryCode == industryCode).Select(i => i.IndustryName).FirstOrDefaultAsync(ct);

        var prefName = person.Profile?.PrefCode is null
            ? null
            : await _db.Prefectures.Where(p => p.PrefCode == person.Profile.PrefCode).Select(p => p.PrefName).FirstOrDefaultAsync(ct);

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
        read.IsSelf = person.IsSelf;
        read.FullName = person.FullName;
        read.FullNameKana = person.FullNameKana;
        read.CompanyName = person.Company?.CompanyName;
        read.IndustryName = industryName;
        read.OccupationName = person.Occupation?.OccupationName;
        read.PrefName = prefName;
        read.JobTitle = person.JobTitle;
        read.Summary = latestCard?.Summary;
        read.Issues = latestCard?.Issues;
        read.LastContactAt = person.LastContactAt;
        read.ContactCount = contactCount;
        read.OpenActionJson = openAction is null
            ? null
            : JsonSerializer.Serialize(new { content = openAction.Content, dueDate = openAction.DueDate });
        read.SearchText = searchText;
        read.CreatedAt = person.CreatedAt;
        read.RefreshedAt = DateTimeOffset.UtcNow;

        await _db.SaveChangesAsync(ct);
    }

    // 職種の業種紐付けを後から変更した場合、その職種を使用中の全人物のindustry_nameを即時再同期する
    // （通常は人物側の書き込み時にしかRefreshAsyncが呼ばれないため、マスタ側の変更だけでは反映されない）
    public async Task RefreshAllForOccupationAsync(string occupationCode, CancellationToken ct = default)
    {
        var personIds = await _db.Persons.Where(p => p.OccupationCode == occupationCode).Select(p => p.PersonId).ToListAsync(ct);
        foreach (var personId in personIds)
        {
            await RefreshAsync(personId, ct);
        }
    }
}
