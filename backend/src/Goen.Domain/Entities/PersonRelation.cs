namespace Goen.Domain.Entities;

// F-005/F-006 人脈グラフ（エッジ）
public class PersonRelation
{
    public Guid RelationId { get; set; }
    public Guid OrgId { get; set; }
    public Guid FromPersonId { get; set; }
    public Guid ToPersonId { get; set; }
    public string RelationType { get; set; } = "community"; // referrer（紹介元） / community（人脈・知人）※同僚・取引先等はperson_profiles.noteへ
    public short Strength { get; set; } = 3; // 1-5
    public bool StrengthIsManual { get; set; }
    public bool IsBidirectional { get; set; }
    public string? Note { get; set; }

    public DateTimeOffset CreatedAt { get; set; }
    public Guid? CreatedBy { get; set; }
    public DateTimeOffset UpdatedAt { get; set; }
    public Guid? UpdatedBy { get; set; }
    public int Version { get; set; }
}
