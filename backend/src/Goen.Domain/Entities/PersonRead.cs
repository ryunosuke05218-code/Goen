namespace Goen.Domain.Entities;

// persons_read: 人物一覧・検索結果表示専用の非正規化された参照モデル（結合0回で取得できる）。
public class PersonRead
{
    public Guid PersonId { get; set; }
    public Guid OrgId { get; set; }
    public Guid OwnerUserId { get; set; }
    public string Visibility { get; set; } = null!;
    public string FullName { get; set; } = null!;
    public string? FullNameKana { get; set; }
    public string? CompanyName { get; set; }
    public string? IndustryName { get; set; }
    public string? PrefName { get; set; }
    public string? JobTitle { get; set; }
    public short Importance { get; set; }
    public string? Summary { get; set; }
    public string? Issues { get; set; }
    public string TagsJson { get; set; } = "[]";
    public DateTimeOffset? LastContactAt { get; set; }
    public int ContactCount { get; set; }
    public string? OpenActionJson { get; set; }
    public string SearchText { get; set; } = string.Empty;
    public DateTimeOffset RefreshedAt { get; set; }
}
