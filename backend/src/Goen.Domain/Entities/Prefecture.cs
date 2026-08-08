namespace Goen.Domain.Entities;

// m_prefecture: 都道府県マスタ。静的マスタのため履歴を持たない。
public class Prefecture
{
    public string PrefCode { get; set; } = null!;
    public string PrefName { get; set; } = null!;
    public string RegionName { get; set; } = null!;
}
