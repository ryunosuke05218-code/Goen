namespace Goen.Api.Dtos;

public record NetworkNodeResponse(
    Guid PersonId,
    string FullName,
    string? CompanyName,
    string? IndustryName,
    string? OccupationName,
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

// F-027: 他ユーザーの人脈図を業種階層までに限定して閲覧する（個別の人物・職種・会社名は含まない）
public record IndustryCountItem(string IndustryName, int Count);

public record IndustryBreakdownResponse(
    Guid TargetUserId,
    string TargetUserDisplayName,
    int TotalCount,
    List<IndustryCountItem> Industries);
