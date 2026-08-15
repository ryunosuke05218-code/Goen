namespace Goen.Api.Dtos;

// 業種マスタ（m_industry）の参照・管理用
public record IndustryItem(string IndustryCode, string IndustryName, bool IsActive);

public record CreateIndustryRequest(string IndustryName);

public record UpdateIndustryRequest(string IndustryName, bool IsActive);

// 職種マスタ（Q-011解消。F-006の人脈図階層グルーピング・人物編集画面の選択肢に使用）
// F-030: 職種追加画面で業種も選択/新規作成できるようIndustryCode/IndustryNameを持つ
public record OccupationTypeItem(
    string OccupationCode,
    string OccupationName,
    string? IndustryCode,
    string? IndustryName,
    bool IsActive);

// IndustryCodeが指定されればそれを使用し、未指定でNewIndustryNameがあれば業種を新規作成（同名があれば再利用）する
public record CreateOccupationTypeRequest(string OccupationName, string? IndustryCode, string? NewIndustryName);

public record UpdateOccupationTypeRequest(string OccupationName, string? IndustryCode, bool IsActive);
