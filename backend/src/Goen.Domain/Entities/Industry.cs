namespace Goen.Domain.Entities;

// m_industry: 業種マスタ。静的マスタのため履歴を持たない。
public class Industry
{
    public string IndustryCode { get; set; } = null!;
    public string IndustryName { get; set; } = null!;
    public string? ParentCode { get; set; }
    public int SortOrder { get; set; }
    public bool IsActive { get; set; } = true;
}
