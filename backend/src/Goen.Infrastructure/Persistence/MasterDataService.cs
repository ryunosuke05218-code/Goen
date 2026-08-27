using Goen.Domain.Entities;
using Microsoft.EntityFrameworkCore;

namespace Goen.Infrastructure.Persistence;

// 業種・職種マスタの検索／find-or-create共通ロジック。人物登録・編集画面のコンボボックス（自由入力で
// 未登録データは即マスタ登録する方式）とMastersController（業種・職種管理画面）の双方から利用する。
public class MasterDataService
{
    private readonly GoenDbContext _db;

    public MasterDataService(GoenDbContext db)
    {
        _db = db;
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

    // 職種名から職種コードを解決する。occupationNameが空ならnull（職種未設定）を返す。
    // 職種が未登録なら新規登録し、その際は引数のindustryCodeForNewOccupation（現在選択中の業種）が
    // あればその業種のみを紐付ける。既存の職種は複数業種にまたがりうる（F-030拡張）ため、
    // 人物登録・編集画面から既存職種の業種紐付けを書き換えることはしない（設定画面の職種管理でのみ変更する）。
    public async Task<string?> ResolveOccupationAsync(string? occupationName, string? industryCodeForNewOccupation, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(occupationName)) return null;
        var name = occupationName.Trim();

        var occupation = await _db.OccupationTypes.FirstOrDefaultAsync(o => o.OccupationName == name, ct);
        if (occupation is null)
        {
            occupation = new OccupationType
            {
                OccupationCode = await GenerateUniqueCodeAsync("O", code => _db.OccupationTypes.AnyAsync(o => o.OccupationCode == code, ct)),
                OccupationName = name,
                SortOrder = 900,
                IsActive = true,
            };
            _db.OccupationTypes.Add(occupation);
            if (industryCodeForNewOccupation is not null)
            {
                _db.OccupationTypeIndustries.Add(new OccupationTypeIndustry
                {
                    OccupationCode = occupation.OccupationCode,
                    IndustryCode = industryCodeForNewOccupation,
                });
            }
            await _db.SaveChangesAsync(ct);
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
