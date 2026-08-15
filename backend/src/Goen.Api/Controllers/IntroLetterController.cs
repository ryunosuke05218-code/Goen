using Goen.Api.Dtos;
using Goen.Infrastructure.Messaging;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Goen.Api.Controllers;

// F-026 紹介文（例文）作成機能。通知機能（F-012、未実装のプレースホルダーのみ）を廃止し、代わりに新設した。
[ApiController]
[Authorize]
[Route("api/intro-letters")]
public class IntroLetterController : ControllerBase
{
    private readonly IntroLetterService _service;

    public IntroLetterController(IntroLetterService service)
    {
        _service = service;
    }

    // 資料ファイル添付（F-026拡張）に対応するためmultipart/form-dataで受け取る（PersonsController.GenerateCardと同じ方式）
    [HttpPost("generate")]
    [RequestSizeLimit(10_000_000)]
    public async Task<ActionResult<GenerateIntroLetterResponse>> Generate(
        [FromForm] Guid targetPersonId,
        [FromForm] string requirement,
        [FromForm] string? tone,
        [FromForm] string? lengthHint,
        [FromForm] string? additionalNotes,
        [FromForm] string? hpUrl,
        IFormFile? file,
        CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(requirement))
        {
            return BadRequest(new { message = "要件を入力してください。" });
        }

        try
        {
            var message = await _service.GenerateAsync(
                targetPersonId, User.GetOrgId(), User.GetUserId(), requirement, tone, lengthHint, additionalNotes, hpUrl, file, ct);
            return Ok(new GenerateIntroLetterResponse(message));
        }
        catch (InvalidOperationException ex)
        {
            return NotFound(new { message = ex.Message });
        }
    }

    [HttpGet("history")]
    public async Task<ActionResult<List<IntroLetterHistoryItemResponse>>> History(CancellationToken ct)
    {
        var items = await _service.GetHistoryAsync(User.GetUserId(), ct);

        return Ok(items.Select(r => new IntroLetterHistoryItemResponse(
            r.RequestId,
            r.TargetPersonId,
            r.TargetPerson.FullName,
            r.Requirement,
            r.Tone,
            r.LengthHint,
            r.AdditionalNotes,
            r.HpUrl,
            r.AttachedFileName,
            r.GeneratedMessage,
            r.CreatedAt)).ToList());
    }
}
