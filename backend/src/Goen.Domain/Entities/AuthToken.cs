namespace Goen.Domain.Entities;

// リフレッシュトークン（F-001: アクセストークン1時間／リフレッシュトークン30日）
public class AuthToken
{
    public Guid TokenId { get; set; }
    public Guid UserId { get; set; }
    public string TokenHash { get; set; } = null!;
    public string? DeviceInfoJson { get; set; }
    public DateTimeOffset IssuedAt { get; set; }
    public DateTimeOffset ExpiresAt { get; set; }
    public DateTimeOffset? RevokedAt { get; set; }
    public DateTimeOffset CreatedAt { get; set; }

    public User User { get; set; } = null!;
}
