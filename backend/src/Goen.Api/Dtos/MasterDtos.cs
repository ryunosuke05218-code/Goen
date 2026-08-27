namespace Goen.Api.Dtos;

// 業種マスタ（m_industry）の参照・管理用
public record IndustryItem(string IndustryCode, string IndustryName, bool IsActive);

public record CreateIndustryRequest(string IndustryName);

public record UpdateIndustryRequest(string IndustryName, bool IsActive);

// 職種マスタ（Q-011解消。F-006の人脈図階層グルーピング・人物編集画面の選択肢に使用）
// F-030拡張: 職種は複数の業種にまたがりうるため、業種は単一ではなく一覧で持つ（固定8業種からの複数選択）
public record OccupationTypeItem(
    string OccupationCode,
    string OccupationName,
    IReadOnlyList<string> IndustryCodes,
    IReadOnlyList<string> IndustryNames,
    bool IsActive);

// 業種は固定8種で運用するため、既存業種コードの複数選択のみ（新規業種の作成は不可）
public record CreateOccupationTypeRequest(string OccupationName, IReadOnlyList<string>? IndustryCodes);

public record UpdateOccupationTypeRequest(string OccupationName, IReadOnlyList<string>? IndustryCodes, bool IsActive);
