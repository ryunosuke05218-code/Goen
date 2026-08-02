namespace Goen.Api.Dtos;

public record RelationSuggestionResponse(
    Guid RelatedPersonId,
    string RelatedPersonName,
    string RelationType,
    string Reason,
    int Strength);

public record ConfirmRelationItem(
    Guid RelatedPersonId,
    string RelationType,
    int Strength,
    bool IsBidirectional = false);

public record ConfirmRelationsRequest(List<ConfirmRelationItem> Relations);

public record NetworkNodeResponse(
    Guid PersonId,
    string FullName,
    string? CompanyName,
    int Importance,
    int Depth,
    bool IsSelf);

public record NetworkEdgeResponse(
    Guid RelationId,
    Guid FromPersonId,
    Guid ToPersonId,
    string RelationType,
    int Strength);

public record NetworkGraphResponse(
    List<NetworkNodeResponse> Nodes,
    List<NetworkEdgeResponse> Edges);
