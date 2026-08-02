using Goen.Api.Dtos;
using Goen.Infrastructure.Rag;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Goen.Api.Controllers;

// 「AI指示」機能: 人脈マップ画面から、自然文で経路・関連人物を尋ねる（人脈マップ自体はAI不使用のまま）。
[ApiController]
[Authorize]
[Route("api/ai-assistant")]
public class AiAssistantController : ControllerBase
{
    private readonly AiAssistantService _assistant;

    public AiAssistantController(AiAssistantService assistant)
    {
        _assistant = assistant;
    }

    [HttpPost("query")]
    public async Task<ActionResult<AiAssistantQueryResponse>> Query(AiAssistantQueryRequest request, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(request.Instruction))
        {
            return BadRequest(new { message = "instructionを入力してください。" });
        }

        var result = await _assistant.AskAsync(User.GetUserId(), User.GetOrgId(), request.Instruction, ct);

        return Ok(new AiAssistantQueryResponse(
            result.Answer,
            result.Routes.Select(r => new AssistantRouteResponse(
                r.Steps.Select(s => new AssistantRouteStepResponse(s.PersonId, s.PersonName, s.RelationTypeFromPrevious)).ToList())).ToList(),
            result.Hints.Select(h => new AssistantHintResponse(h.PersonId, h.PersonName, h.Reason, h.Excerpt)).ToList()));
    }
}
