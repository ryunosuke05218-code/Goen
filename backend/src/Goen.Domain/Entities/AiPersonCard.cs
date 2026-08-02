namespace Goen.Domain.Entities;

// F-010 AI人物カルテ。世代管理テーブル（生成のたびに新規行、最新のみ IsLatest = true）。
public class AiPersonCard
{
    public Guid CardId { get; set; }
    public Guid PersonId { get; set; }
    public int Generation { get; set; }
    public bool IsLatest { get; set; } = true;
    public string? Summary { get; set; }
    public string? Business { get; set; }
    public string? Issues { get; set; }
    public string? IntroducerName { get; set; }
    public string? Hobby { get; set; }
    public string? Strengths { get; set; }
    public string? WantedSummary { get; set; }
    public string FieldSourcesJson { get; set; } = "{}"; // 項目ごとの生成元 "ai" / "user"
    public string LlmModel { get; set; } = null!;
    public DateTimeOffset GeneratedAt { get; set; }
    public Guid[] InputContactIds { get; set; } = Array.Empty<Guid>();

    public DateTimeOffset CreatedAt { get; set; }
    public Guid? CreatedBy { get; set; }
    public DateTimeOffset UpdatedAt { get; set; }
    public Guid? UpdatedBy { get; set; }
    public int Version { get; set; }

    public Person Person { get; set; } = null!;
}
