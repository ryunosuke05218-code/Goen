namespace Goen.Domain.Entities;

// m_occupation_type_industry: 職種×業種（多対多）。設定画面の職種追加・編集で複数業種を選択できる。
public class OccupationTypeIndustry
{
    public string OccupationCode { get; set; } = null!;
    public string IndustryCode { get; set; } = null!;
}
