using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using Goen.Domain.Entities;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.Tokens;

namespace Goen.Infrastructure.Security;

public record IssuedTokens(string AccessToken, DateTimeOffset AccessTokenExpiresAt, string RefreshToken, DateTimeOffset RefreshTokenExpiresAt);

// F-001 ログイン機能: アクセストークン(JWT)とリフレッシュトークン(不透明なランダム文字列)を発行する。
// リフレッシュトークンは平文をDBに保存せず、ハッシュ値のみを auth_tokens.token_hash に保存する。
public class JwtTokenService
{
    private readonly JwtOptions _options;

    public JwtTokenService(IOptions<JwtOptions> options)
    {
        _options = options.Value;
    }

    public (string token, DateTimeOffset expiresAt) CreateAccessToken(User user)
    {
        var expiresAt = DateTimeOffset.UtcNow.AddMinutes(_options.AccessTokenMinutes);
        var claims = new[]
        {
            new Claim(JwtRegisteredClaimNames.Sub, user.UserId.ToString()),
            new Claim("org_id", user.OrgId.ToString()),
            new Claim(ClaimTypes.Role, user.Role),
            new Claim(JwtRegisteredClaimNames.Email, user.Email),
        };

        var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(_options.SigningKey));
        var credentials = new SigningCredentials(key, SecurityAlgorithms.HmacSha256);

        var token = new JwtSecurityToken(
            issuer: _options.Issuer,
            audience: _options.Audience,
            claims: claims,
            expires: expiresAt.UtcDateTime,
            signingCredentials: credentials);

        return (new JwtSecurityTokenHandler().WriteToken(token), expiresAt);
    }

    public (string plainToken, string tokenHash, DateTimeOffset expiresAt) CreateRefreshToken()
    {
        var plainToken = Convert.ToBase64String(RandomNumberGenerator.GetBytes(32));
        var tokenHash = HashRefreshToken(plainToken);
        var expiresAt = DateTimeOffset.UtcNow.AddDays(_options.RefreshTokenDays);
        return (plainToken, tokenHash, expiresAt);
    }

    public string HashRefreshToken(string plainToken)
    {
        var bytes = SHA256.HashData(Encoding.UTF8.GetBytes(plainToken));
        return Convert.ToBase64String(bytes);
    }
}
