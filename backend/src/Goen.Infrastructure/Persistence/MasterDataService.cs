using Goen.Domain.Entities;
using Microsoft.EntityFrameworkCore;

namespace Goen.Infrastructure.Persistence;

// 業種・職種マスタの検索／find-or-create共通ロジック。人物登録・編集画面のコンボボックス（自由入力で
// 未登録データは即マスタ登録する方式）とMastersController（業種・職種管理画面）の双方から利用する。
public class MasterDataService
{
    private readonly GoenDbContext _db;
    private readonly PersonReadSyncService _readSync;

    public MasterDataService(GoenDbContext db, PersonReadSyncService readSync)
    {
        _db = db;
        _readSync = readSync;
    }

    // 業種名から業種コードを解決する。完全一致（大小区別なし）する既存業種があればそれを再利用し、なければ新規登録する。
    public async Task<string> ResolveIndustryAsync(string industryName, CancellationToken ct)
    {
        var name = industryName.Trim();
        var existing = await _db.Industries.FirstOrDefaultAsync(i => i.IndustryName == name, ct);
        if (existing is not null) return existing.IndustryCode;

        var industry = new Industry
        {
            IndustryCode = await GenerateUniqueCodeAsync("I", code => _db.Industries.AnyAsync(i => i.IndustryCode == code, ct)),
            IndustryName = name,
            SortOrder = 900,
            IsActive = true,
        };
        _db.Industries.Add(industry);
        await _db.SaveChangesAsync(ct);
        return industry.IndustryCode;
    }

    // 職種名（＋任意の業種名）から職種コードを解決する。occupationNameが空ならnull（職種未設定）を返す。
    // 職種が未登録なら業種と一緒に新規登録し、既存の職種で業種名が現在の紐付けと異なる場合はその職種の業種紐付け
    // 自体を更新する（同じ職種を使う全人物に影響するため、対象人物のpersons_readも即時再同期する）。
    public async Task<string?> ResolveOccupationAsync(string? occupationName, string? industryName, CancellationToken ct)
    {
        string? industryCode = null;
        if (!string.IsNullOrWhiteSpace(industryName))
        {
            industryCode = await ResolveIndustryAsync(industryName, ct);
        }

        if (string.IsNullOrWhiteSpace(occupationName)) return null;
        var name = occupationName.Trim();

        var occupation = await _db.OccupationTypes.FirstOrDefaultAsync(o => o.OccupationName == name, ct);
        if (occupation is null)
        {
            occupation = new OccupationType
            {
                OccupationCode = await GenerateUniqueCodeAsync("O", code => _db.OccupationTypes.AnyAsync(o => o.OccupationCode == code, ct)),
                OccupationName = name,
                IndustryCode = industryCode,
                SortOrder = 900,
                IsActive = true,
            };
            _db.OccupationTypes.Add(occupation);
            await _db.SaveChangesAsync(ct);
        }
        else if (industryCode is not null && occupation.IndustryCode != industryCode)
        {
            occupation.IndustryCode = industryCode;
            await _db.SaveChangesAsync(ct);
            await _readSync.RefreshAllForOccupationAsync(occupation.OccupationCode, ct);
        }

        return occupation.OccupationCode;
    }

    // varchar(10)のコード列に収まる短い一意コードを生成する（衝突確率は無視できるほど低いが念のため再試行する）
    public static async Task<string> GenerateUniqueCodeAsync(string prefix, Func<string, Task<bool>> existsAsync)
    {
        for (var attempt = 0; attempt < 5; attempt++)
        {
            var code = $"{prefix}{Guid.NewGuid():N}"[..10].ToUpperInvariant();
            if (!await existsAsync(code)) return code;
        }
        throw new InvalidOperationException("コードの生成に失敗しました。");
    }
}
