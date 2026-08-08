namespace Goen.Domain.Entities;

// m_occupation_type: 職種マスタ（F-006の人脈図階層グルーピングに使用）。静的マスタのため履歴を持たない。
public class OccupationType
{
    public string OccupationCode { get; set; } = null!;
    public string OccupationName { get; set; } = null!;
    public int SortOrder { get; set; }
    public bool IsActive { get; set; } = true;
}
