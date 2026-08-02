namespace Goen.Infrastructure.Security;

public class JwtOptions
{
    public const string SectionName = "Jwt";

    public string Issuer { get; set; } = "goen-api";
    public string Audience { get; set; } = "goen-app";
    public string SigningKey { get; set; } = null!;
    public int AccessTokenMinutes { get; set; } = 60;      // F-001: アクセストークン有効期間1時間
    public int RefreshTokenDays { get; set; } = 30;         // F-001: リフレッシュトークン有効期間30日
}
