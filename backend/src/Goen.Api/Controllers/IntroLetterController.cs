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

    [HttpPost("generate")]
    public async Task<ActionResult<GenerateIntroLetterResponse>> Generate(GenerateIntroLetterRequest request, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(request.Requirement))
        {
            return BadRequest(new { message = "要件を入力してください。" });
        }

        try
        {
            var message = await _service.GenerateAsync(
                request.TargetPersonId, User.GetOrgId(), request.Requirement, request.Tone, request.LengthHint, request.AdditionalNotes, ct);
            return Ok(new GenerateIntroLetterResponse(message));
        }
        catch (InvalidOperationException ex)
        {
            return NotFound(new { message = ex.Message });
        }
    }
}
