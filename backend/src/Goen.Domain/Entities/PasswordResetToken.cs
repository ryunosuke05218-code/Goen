namespace Goen.Domain.Entities;

// パスワードリセット用の6桁コード。平文は保存せずハッシュのみ保持する（AuthTokenのリフレッシュトークンと同じ方針）。
public class PasswordResetToken
{
    public Guid TokenId { get; set; }
    public Guid UserId { get; set; }
    public string CodeHash { get; set; } = null!;
    public DateTimeOffset ExpiresAt { get; set; }
    public DateTimeOffset? UsedAt { get; set; }
    public DateTimeOffset CreatedAt { get; set; }

    public User User { get; set; } = null!;
}
