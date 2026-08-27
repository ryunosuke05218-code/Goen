namespace Goen.Domain.Entities;

public class Person
{
    public Guid PersonId { get; set; }
    public Guid OrgId { get; set; }
    public Guid OwnerUserId { get; set; }
    public Guid? CompanyId { get; set; }
    public string FullName { get; set; } = null!;
    public string? FullNameKana { get; set; }
    public string? Department { get; set; }
    public string? JobTitle { get; set; }
    public string? OccupationCode { get; set; }
    // 業種。職種が複数業種にまたがりうる（OccupationTypeIndustry）ため、職種経由の導出ではなく人物ごとに直接持たせる
    public string? IndustryCode { get; set; }
    public string Visibility { get; set; } = "private"; // private / team / org
    public DateOnly? FirstMetAt { get; set; }
    public string? MetPlace { get; set; }
    public DateTimeOffset? LastContactAt { get; set; }
    public Guid? IntroducerPersonId { get; set; }
    public string SourceType { get; set; } = "manual"; // card_ocr / manual / import
    public bool IsSelf { get; set; } // 利用者自身を表す人物カルテ（1ユーザーにつき最大1件）

    public DateTimeOffset CreatedAt { get; set; }
    public Guid? CreatedBy { get; set; }
    public DateTimeOffset UpdatedAt { get; set; }
    public Guid? UpdatedBy { get; set; }
    public int Version { get; set; }

    public Company? Company { get; set; }
    public OccupationType? Occupation { get; set; }
    public Person? IntroducerPerson { get; set; }
    public PersonProfile? Profile { get; set; }
    public ICollection<Contact> Contacts { get; set; } = new List<Contact>();
    public ICollection<AiPersonCard> Cards { get; set; } = new List<AiPersonCard>();
    public ICollection<NextAction> NextActions { get; set; } = new List<NextAction>();
}
