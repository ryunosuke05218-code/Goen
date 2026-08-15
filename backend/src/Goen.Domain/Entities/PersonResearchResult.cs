namespace Goen.Domain.Entities;

// F-038: 氏名・会社名をもとにAIがWeb検索し、公開情報から生成した参考情報（要約＋出典）。
// ai_person_cards（ユーザー自身のデータのみを根拠とする）とは異なり公開Web情報を根拠にするため、
// 出典（SourcesJson）を必須で保持する。世代管理は行わず、人物1件につき最新1件のみ（再実行のたびに上書き）。
public class PersonResearchResult
{
    public Guid PersonId { get; set; }
    public Guid OrgId { get; set; }
    public string Summary { get; set; } = null!;
    public string SourcesJson { get; set; } = "[]"; // [{"title": "...", "url": "..."}, ...]
    public string LlmModel { get; set; } = null!;
    public DateTimeOffset GeneratedAt { get; set; }

    public DateTimeOffset CreatedAt { get; set; }
    public Guid? CreatedBy { get; set; }
    public DateTimeOffset UpdatedAt { get; set; }
    public Guid? UpdatedBy { get; set; }
    public int Version { get; set; }

    public Person Person { get; set; } = null!;
}
