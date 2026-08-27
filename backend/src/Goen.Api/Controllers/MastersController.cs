using Goen.Api.Dtos;
using Goen.Domain.Entities;
using Goen.Infrastructure.Persistence;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace Goen.Api.Controllers;

// 業種・職種マスタの参照・管理用。
// F-006の人脈図の階層グルーピング元データであり、F-030の職種追加画面・業種/職種管理画面から利用される。
[ApiController]
[Authorize]
[Route("api/masters")]
public class MastersController : ControllerBase
{
    private readonly GoenDbContext _db;
    private readonly PersonReadSyncService _readSync;
    private readonly MasterDataService _masterData;

    public MastersController(GoenDbContext db, PersonReadSyncService readSync, MasterDataService masterData)
    {
        _db = db;
        _readSync = readSync;
        _masterData = masterData;
    }

    // F-030: 業種選択肢の取得（管理画面では非活性のものも編集対象になるため全件返す。ピッカー側で活性のみに絞る）
    [HttpGet("industries")]
    public async Task<ActionResult<IReadOnlyList<IndustryItem>>> ListIndustries(CancellationToken ct)
    {
        var items = await _db.Industries
            .OrderBy(i => i.SortOrder).ThenBy(i => i.IndustryName)
            .Select(i => new IndustryItem(i.IndustryCode, i.IndustryName, i.IsActive))
            .ToListAsync(ct);

        return Ok(items);
    }

    // F-030: 職種追加画面で「新しい業種を作成」した際に呼ばれる。同名の業種が既にあれば再利用する。
    [HttpPost("industries")]
    public async Task<ActionResult<IndustryItem>> CreateIndustry(CreateIndustryRequest request, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(request.IndustryName)) return BadRequest("業種名を入力してください。");

        var code = await _masterData.ResolveIndustryAsync(request.IndustryName, ct);
        var industry = await _db.Industries.FirstAsync(i => i.IndustryCode == code, ct);

        return Ok(new IndustryItem(industry.IndustryCode, industry.IndustryName, industry.IsActive));
    }

    // 業種・職種管理画面: 業種名の変更／有効・無効の切り替え
    [HttpPut("industries/{code}")]
    public async Task<ActionResult<IndustryItem>> UpdateIndustry(string code, UpdateIndustryRequest request, CancellationToken ct)
    {
        var industry = await _db.Industries.FirstOrDefaultAsync(i => i.IndustryCode == code, ct);
        if (industry is null) return NotFound();

        var name = request.IndustryName.Trim();
        if (string.IsNullOrEmpty(name)) return BadRequest("業種名を入力してください。");

        industry.IndustryName = name;
        industry.IsActive = request.IsActive;
        await _db.SaveChangesAsync(ct);

        return Ok(new IndustryItem(industry.IndustryCode, industry.IndustryName, industry.IsActive));
    }

    // F-006: 人物編集画面の職種選択肢、人脈図の階層グルーピングの元データ（管理画面では非活性も表示するため全件返す）
    // F-030拡張: 職種は複数業種にまたがりうるため、業種は一覧で返す。
    [HttpGet("occupation-types")]
    public async Task<ActionResult<IReadOnlyList<OccupationTypeItem>>> ListOccupationTypes(CancellationToken ct)
    {
        var occupations = await _db.OccupationTypes.OrderBy(o => o.SortOrder).ThenBy(o => o.OccupationName).ToListAsync(ct);
        var links = await (
            from oi in _db.OccupationTypeIndustries
            join i in _db.Industries on oi.IndustryCode equals i.IndustryCode
            select new { oi.OccupationCode, i.IndustryCode, i.IndustryName }
        ).ToListAsync(ct);
        var linksByOccupation = links.ToLookup(l => l.OccupationCode);

        var items = occupations.Select(o =>
        {
            var occupationLinks = linksByOccupation[o.OccupationCode].ToList();
            return new OccupationTypeItem(
                o.OccupationCode, o.OccupationName,
                occupationLinks.Select(l => l.IndustryCode).ToList(),
                occupationLinks.Select(l => l.IndustryName).ToList(),
                o.IsActive);
        }).ToList();

        return Ok(items);
    }

    // F-030拡張: 職種追加画面。業種は固定8種からの複数選択のみ（新規業種の作成は不可）。
    [HttpPost("occupation-types")]
    public async Task<ActionResult<OccupationTypeItem>> CreateOccupationType(CreateOccupationTypeRequest request, CancellationToken ct)
    {
        var name = request.OccupationName.Trim();
        if (string.IsNullOrEmpty(name)) return BadRequest("職種名を入力してください。");

        var industryCodes = await ValidateIndustryCodesAsync(request.IndustryCodes, ct);
        if (industryCodes is null) return BadRequest("指定された業種が見つかりません。");

        var existing = await _db.OccupationTypes.FirstOrDefaultAsync(o => o.OccupationName == name, ct);
        if (existing is not null) return Ok(await ToItemAsync(existing, ct));

        var occupation = new OccupationType
        {
            OccupationCode = await MasterDataService.GenerateUniqueCodeAsync("O", code => _db.OccupationTypes.AnyAsync(o => o.OccupationCode == code, ct)),
            OccupationName = name,
            SortOrder = 900,
            IsActive = true,
        };
        _db.OccupationTypes.Add(occupation);
        foreach (var industryCode in industryCodes)
        {
            _db.OccupationTypeIndustries.Add(new OccupationTypeIndustry { OccupationCode = occupation.OccupationCode, IndustryCode = industryCode });
        }
        await _db.SaveChangesAsync(ct);

        return Ok(await ToItemAsync(occupation, ct));
    }

    // 業種・職種管理画面: 職種名・紐づく業種（複数選択）の変更／有効・無効の切り替え
    [HttpPut("occupation-types/{code}")]
    public async Task<ActionResult<OccupationTypeItem>> UpdateOccupationType(string code, UpdateOccupationTypeRequest request, CancellationToken ct)
    {
        var occupation = await _db.OccupationTypes.FirstOrDefaultAsync(o => o.OccupationCode == code, ct);
        if (occupation is null) return NotFound();

        var name = request.OccupationName.Trim();
        if (string.IsNullOrEmpty(name)) return BadRequest("職種名を入力してください。");

        var industryCodes = await ValidateIndustryCodesAsync(request.IndustryCodes, ct);
        if (industryCodes is null) return BadRequest("指定された業種が見つかりません。");

        // persons_read.occupation_nameはこの職種を選んでいる人物ごとに非正規化されているため、
        // 職種名を変更した場合はすでに登録済みの人物分もここで再同期する
        // （通常はPersonReadSyncServiceが人物側の書き込み時にしか呼ばれないため、マスタ側の変更だけでは反映されない）。
        // 業種の紐付けは人物のindustry_codeとは独立（F-030拡張）のため、変更しても人物側の再同期は不要。
        var nameChanged = occupation.OccupationName != name;

        occupation.OccupationName = name;
        occupation.IsActive = request.IsActive;

        var existingLinks = await _db.OccupationTypeIndustries.Where(oi => oi.OccupationCode == code).ToListAsync(ct);
        _db.OccupationTypeIndustries.RemoveRange(existingLinks);
        foreach (var industryCode in industryCodes)
        {
            _db.OccupationTypeIndustries.Add(new OccupationTypeIndustry { OccupationCode = code, IndustryCode = industryCode });
        }

        await _db.SaveChangesAsync(ct);

        if (nameChanged)
        {
            await _readSync.RefreshAllForOccupationAsync(code, ct);
        }

        return Ok(await ToItemAsync(occupation, ct));
    }

    // 指定された業種コード群が実在するか検証する（存在しないコードが1件でもあればnullを返す）。null/空はOK（未設定）。
    private async Task<List<string>?> ValidateIndustryCodesAsync(IReadOnlyList<string>? industryCodes, CancellationToken ct)
    {
        var codes = (industryCodes ?? Array.Empty<string>()).Distinct().ToList();
        if (codes.Count == 0) return codes;

        var foundCount = await _db.Industries.CountAsync(i => codes.Contains(i.IndustryCode), ct);
        return foundCount == codes.Count ? codes : null;
    }

    private async Task<OccupationTypeItem> ToItemAsync(OccupationType occupation, CancellationToken ct)
    {
        var links = await (
            from oi in _db.OccupationTypeIndustries
            join i in _db.Industries on oi.IndustryCode equals i.IndustryCode
            where oi.OccupationCode == occupation.OccupationCode
            select new { i.IndustryCode, i.IndustryName }
        ).ToListAsync(ct);
        return new OccupationTypeItem(
            occupation.OccupationCode, occupation.OccupationName,
            links.Select(l => l.IndustryCode).ToList(),
            links.Select(l => l.IndustryName).ToList(),
            occupation.IsActive);
    }
}
