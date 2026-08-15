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
    [HttpGet("occupation-types")]
    public async Task<ActionResult<IReadOnlyList<OccupationTypeItem>>> ListOccupationTypes(CancellationToken ct)
    {
        var items = await (
            from o in _db.OccupationTypes
            join i in _db.Industries on o.IndustryCode equals i.IndustryCode into industries
            from i in industries.DefaultIfEmpty()
            orderby o.SortOrder, o.OccupationName
            select new OccupationTypeItem(o.OccupationCode, o.OccupationName, o.IndustryCode, i == null ? null : i.IndustryName, o.IsActive)
        ).ToListAsync(ct);

        return Ok(items);
    }

    // F-030: 職種追加画面。業種はコード指定（既存を選択）か、NewIndustryName指定（新規作成、同名は再利用）のどちらかで紐付ける。
    [HttpPost("occupation-types")]
    public async Task<ActionResult<OccupationTypeItem>> CreateOccupationType(CreateOccupationTypeRequest request, CancellationToken ct)
    {
        var name = request.OccupationName.Trim();
        if (string.IsNullOrEmpty(name)) return BadRequest("職種名を入力してください。");

        var industryCode = string.IsNullOrWhiteSpace(request.IndustryCode) ? null : request.IndustryCode;
        if (industryCode is null && !string.IsNullOrWhiteSpace(request.NewIndustryName))
        {
            industryCode = await _masterData.ResolveIndustryAsync(request.NewIndustryName, ct);
        }

        var existing = await _db.OccupationTypes.FirstOrDefaultAsync(o => o.OccupationName == name, ct);
        if (existing is not null) return Ok(await ToItemAsync(existing, ct));

        var occupation = new OccupationType
        {
            OccupationCode = await MasterDataService.GenerateUniqueCodeAsync("O", code => _db.OccupationTypes.AnyAsync(o => o.OccupationCode == code, ct)),
            OccupationName = name,
            IndustryCode = industryCode,
            SortOrder = 900,
            IsActive = true,
        };
        _db.OccupationTypes.Add(occupation);
        await _db.SaveChangesAsync(ct);

        return Ok(await ToItemAsync(occupation, ct));
    }

    // 業種・職種管理画面: 職種名・紐づく業種の変更／有効・無効の切り替え
    [HttpPut("occupation-types/{code}")]
    public async Task<ActionResult<OccupationTypeItem>> UpdateOccupationType(string code, UpdateOccupationTypeRequest request, CancellationToken ct)
    {
        var occupation = await _db.OccupationTypes.FirstOrDefaultAsync(o => o.OccupationCode == code, ct);
        if (occupation is null) return NotFound();

        var name = request.OccupationName.Trim();
        if (string.IsNullOrEmpty(name)) return BadRequest("職種名を入力してください。");

        var newIndustryCode = string.IsNullOrWhiteSpace(request.IndustryCode) ? null : request.IndustryCode;
        var industryChanged = occupation.IndustryCode != newIndustryCode;

        occupation.OccupationName = name;
        occupation.IndustryCode = newIndustryCode;
        occupation.IsActive = request.IsActive;
        await _db.SaveChangesAsync(ct);

        // persons_read.industry_nameはこの職種を選んでいる人物ごとに非正規化されているため、
        // 業種の紐付けを変更した場合はすでに登録済みの人物分もここで再同期する
        // （通常はPersonReadSyncServiceが人物側の書き込み時にしか呼ばれないため、マスタ側の変更だけでは反映されない）。
        if (industryChanged)
        {
            await _readSync.RefreshAllForOccupationAsync(code, ct);
        }

        return Ok(await ToItemAsync(occupation, ct));
    }

    private async Task<OccupationTypeItem> ToItemAsync(OccupationType occupation, CancellationToken ct)
    {
        var industryName = occupation.IndustryCode is null
            ? null
            : await _db.Industries.Where(i => i.IndustryCode == occupation.IndustryCode).Select(i => i.IndustryName).FirstOrDefaultAsync(ct);
        return new OccupationTypeItem(occupation.OccupationCode, occupation.OccupationName, occupation.IndustryCode, industryName, occupation.IsActive);
    }
}
