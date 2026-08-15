namespace Goen.Domain.Entities;

// AI指示（人脈相談）の質問・回答履歴。人脈図画面から過去のやり取りを読み返せるようにするための記録（追記のみ）。
public class AiAssistantQuery
{
    public Guid QueryId { get; set; }
    public Guid OrgId { get; set; }
    public Guid OwnerUserId { get; set; }
    public string Instruction { get; set; } = null!;
    public string Answer { get; set; } = null!;
    public string RoutesJson { get; set; } = "[]"; // AssistantRoute[]（自分→…→対象人物の紹介チェーン）
    public string HintsJson { get; set; } = "[]"; // AssistantHint[]（RAG検索でヒットした関連人物）
    public DateTimeOffset CreatedAt { get; set; }
}
