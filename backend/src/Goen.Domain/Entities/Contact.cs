namespace Goen.Domain.Entities;

public class Contact
{
    public Guid ContactId { get; set; }
    public Guid OrgId { get; set; }
    public Guid PersonId { get; set; }
    public Guid UserId { get; set; }
    public string ContactType { get; set; } = "other"; // card_exchange / one_on_one / meeting / referral / event / other
    public DateTimeOffset OccurredAt { get; set; }
    public string? Place { get; set; }
    public string? Note { get; set; }
    public string? NoteSummary { get; set; } // F-011拡張: 接点メモのAI要約。ボタン押下時のみ生成・上書きされる
    public bool HasMedia { get; set; }

    public DateTimeOffset CreatedAt { get; set; }
    public Guid? CreatedBy { get; set; }
    public DateTimeOffset UpdatedAt { get; set; }
    public Guid? UpdatedBy { get; set; }
    public int Version { get; set; }

    public Person Person { get; set; } = null!;
    public ICollection<ContactMedia> Media { get; set; } = new List<ContactMedia>();
    public ICollection<Transcript> Transcripts { get; set; } = new List<Transcript>();
}
