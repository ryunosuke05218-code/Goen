namespace Goen.Api.Dtos;

public record AiAssistantQueryRequest(string Instruction);

public record AssistantRouteStepResponse(Guid PersonId, string PersonName, string? RelationTypeFromPrevious);

public record AssistantRouteResponse(List<AssistantRouteStepResponse> Steps);

public record AssistantHintResponse(Guid PersonId, string PersonName, string Reason, string Excerpt);

public record AiAssistantQueryResponse(
    string Answer,
    List<AssistantRouteResponse> Routes,
    List<AssistantHintResponse> Hints);
