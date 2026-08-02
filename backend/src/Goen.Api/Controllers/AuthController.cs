using Goen.Api.Dtos;
using Goen.Domain.Entities;
using Goen.Infrastructure.Persistence;
using Goen.Infrastructure.Security;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Caching.Memory;

namespace Goen.Api.Controllers;

// F-001 ログイン機能
[ApiController]
[Route("api/auth")]
public class AuthController : ControllerBase
{
    private const int MaxFailedAttempts = 5;
    private static readonly TimeSpan LockoutDuration = TimeSpan.FromMinutes(15);

    private readonly GoenDbContext _db;
    private readonly Pbkdf2PasswordHasher _hasher;
    private readonly JwtTokenService _tokenService;
    private readonly IMemoryCache _cache;

    public AuthController(GoenDbContext db, Pbkdf2PasswordHasher hasher, JwtTokenService tokenService, IMemoryCache cache)
    {
        _db = db;
        _hasher = hasher;
        _tokenService = tokenService;
        _cache = cache;
    }

    [HttpPost("login")]
    public async Task<ActionResult<AuthResponse>> Login(LoginRequest request, CancellationToken ct)
    {
        var lockoutKey = $"login-lockout:{request.Email.Trim().ToLowerInvariant()}";
        if (_cache.TryGetValue(lockoutKey, out DateTimeOffset lockedUntil) && lockedUntil > DateTimeOffset.UtcNow)
        {
            return Problem(
                title: "アカウントが一時的にロックされています。",
                detail: $"{lockedUntil:u} 以降に再度お試しください。",
                statusCode: StatusCodes.Status423Locked);
        }

        var user = await _db.Users.FirstOrDefaultAsync(
            u => u.Email.ToLower() == request.Email.Trim().ToLowerInvariant(), ct);

        if (user is null || user.Status != "active" || !_hasher.Verify(request.Password, user.PasswordHash))
        {
            RegisterFailedAttempt(lockoutKey);
            return Unauthorized(new { message = "メールアドレスまたはパスワードが正しくありません。" });
        }

        _cache.Remove(lockoutKey);

        user.LastLoginAt = DateTimeOffset.UtcNow;
        var tokens = await IssueTokensAsync(user, ct);
        await _db.SaveChangesAsync(ct);

        return Ok(ToAuthResponse(tokens, user));
    }

    [HttpPost("refresh")]
    public async Task<ActionResult<AuthResponse>> Refresh(RefreshRequest request, CancellationToken ct)
    {
        var tokenHash = _tokenService.HashRefreshToken(request.RefreshToken);
        var stored = await _db.AuthTokens
            .Include(t => t.User)
            .FirstOrDefaultAsync(t => t.TokenHash == tokenHash, ct);

        if (stored is null || stored.RevokedAt is not null || stored.ExpiresAt <= DateTimeOffset.UtcNow)
        {
            // F-001 例外・エラー処理: リフレッシュトークン失効時は再度メールアドレス認証を求める
            return Unauthorized(new { message = "リフレッシュトークンが無効です。再度ログインしてください。" });
        }

        stored.RevokedAt = DateTimeOffset.UtcNow; // ローテーション: 使用済みトークンは無効化する
        var tokens = await IssueTokensAsync(stored.User, ct);
        await _db.SaveChangesAsync(ct);

        return Ok(ToAuthResponse(tokens, stored.User));
    }

    private async Task<IssuedTokens> IssueTokensAsync(User user, CancellationToken ct)
    {
        var (accessToken, accessExpiresAt) = _tokenService.CreateAccessToken(user);
        var (refreshPlain, refreshHash, refreshExpiresAt) = _tokenService.CreateRefreshToken();

        _db.AuthTokens.Add(new AuthToken
        {
            TokenId = Guid.NewGuid(),
            UserId = user.UserId,
            TokenHash = refreshHash,
            IssuedAt = DateTimeOffset.UtcNow,
            ExpiresAt = refreshExpiresAt,
            CreatedAt = DateTimeOffset.UtcNow,
        });

        return new IssuedTokens(accessToken, accessExpiresAt, refreshPlain, refreshExpiresAt);
    }

    private void RegisterFailedAttempt(string lockoutKey)
    {
        var countKey = $"{lockoutKey}:count";
        var count = _cache.GetOrCreate(countKey, e =>
        {
            e.AbsoluteExpirationRelativeToNow = LockoutDuration;
            return 0;
        });
        count++;
        _cache.Set(countKey, count, LockoutDuration);

        if (count >= MaxFailedAttempts)
        {
            _cache.Set(lockoutKey, DateTimeOffset.UtcNow.Add(LockoutDuration), LockoutDuration);
        }
    }

    private static AuthResponse ToAuthResponse(IssuedTokens tokens, User user) => new(
        tokens.AccessToken,
        tokens.AccessTokenExpiresAt,
        tokens.RefreshToken,
        tokens.RefreshTokenExpiresAt,
        new UserSummary(user.UserId, user.Email, user.DisplayName, user.Role));
}
