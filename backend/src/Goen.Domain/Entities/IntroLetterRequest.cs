namespace Goen.Domain.Entities;

// 紹介文（例文）作成の依頼・生成結果の履歴（F-026拡張）。過去に依頼した内容とAIの回答を読み返せるようにする記録（追記のみ）。
public class IntroLetterRequest
{
    public Guid RequestId { get; set; }
    public Guid OrgId { get; set; }
    public Guid OwnerUserId { get; set; }
    public Guid TargetPersonId { get; set; }
    public string Requirement { get; set; } = null!;
    public string? Tone { get; set; }
    public string? LengthHint { get; set; }
    public string? AdditionalNotes { get; set; }
    public string? HpUrl { get; set; }
    public string? AttachedFileName { get; set; } // 添付ファイルは保存せずファイル名のみ記録（履歴は再閲覧用途のみのため）
    public string GeneratedMessage { get; set; } = null!;
    public DateTimeOffset CreatedAt { get; set; }

    public Person TargetPerson { get; set; } = null!;
}
