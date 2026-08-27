using System.Security.Cryptography;
using Goen.Api.Dtos;
using Goen.Domain.Entities;
using Goen.Infrastructure.Messaging;
using Goen.Infrastructure.Persistence;
using Goen.Infrastructure.Security;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.Logging;

namespace Goen.Api.Controllers;

// F-001 ログイン機能。自己登録（F-001拡張）・パスワードリセットも本コントローラで扱う。
// サブスク未契約・期限切れでもログイン自体はできる必要があるため、課金ゲートの対象外とする。
[ApiController]
[Route("api/auth")]
[AllowInactiveSubscription]
public class AuthController : ControllerBase
{
    private const int MaxFailedAttempts = 5;
    private static readonly TimeSpan LockoutDuration = TimeSpan.FromMinutes(15);
    private static readonly TimeSpan ResetCodeValidity = TimeSpan.FromMinutes(15);
    private const int MinPasswordLength = 8;

    private readonly GoenDbContext _db;
    private readonly Pbkdf2PasswordHasher _hasher;
    private readonly JwtTokenService _tokenService;
    private readonly IMemoryCache _cache;
    private readonly IEmailService _email;
    private readonly ILogger<AuthController> _logger;

    public AuthController(
        GoenDbContext db, Pbkdf2PasswordHasher hasher, JwtTokenService tokenService, IMemoryCache cache,
        IEmailService email, ILogger<AuthController> logger)
    {
        _db = db;
        _hasher = hasher;
        _tokenService = tokenService;
        _cache = cache;
        _email = email;
        _logger = logger;
    }

    // 自己登録: 登録者ごとに新しい組織（personalプラン）を作成し、その最初のユーザーとして登録する。
    // チーム共有（F-019、既存の組織へ参加する仕組み）は未実装のため、現状は必ず新規組織を作る。
    [HttpPost("register")]
    public async Task<ActionResult<AuthResponse>> Register(RegisterRequest request, CancellationToken ct)
    {
        var email = request.Email.Trim();
        if (string.IsNullOrWhiteSpace(email) || string.IsNullOrWhiteSpace(request.DisplayName))
        {
            return BadRequest(new { message = "メールアドレスと表示名を入力してください。" });
        }
        if (request.Password.Length < MinPasswordLength)
        {
            return BadRequest(new { message = $"パスワードは{MinPasswordLength}文字以上で設定してください。" });
        }

        var exists = await _db.Users.AnyAsync(u => u.Email.ToLower() == email.ToLowerInvariant(), ct);
        if (exists)
        {
            return Conflict(new { message = "このメールアドレスは既に登録されています。" });
        }

        var now = DateTimeOffset.UtcNow;
        var org = new Organization
        {
            OrgId = Guid.NewGuid(),
            OrgName = $"{request.DisplayName}の個人アカウント",
            PlanType = "personal",
            CreatedAt = now,
            UpdatedAt = now,
        };
        _db.Organizations.Add(org);

        var user = new User
        {
            UserId = Guid.NewGuid(),
            OrgId = org.OrgId,
            Email = email,
            PasswordHash = _hasher.Hash(request.Password),
            DisplayName = request.DisplayName,
            Role = "org_admin", // 個人アカウントの唯一のユーザーのため管理者権限を持たせる
            Status = "active",
            LastLoginAt = now,
            CreatedAt = now,
            UpdatedAt = now,
        };
        _db.Users.Add(user);
        await _db.SaveChangesAsync(ct);

        org.CreatedBy = user.UserId;
        org.UpdatedBy = user.UserId;
        user.CreatedBy = user.UserId;
        user.UpdatedBy = user.UserId;

        var tokens = await IssueTokensAsync(user, ct);
        await _db.SaveChangesAsync(ct);

        return Ok(ToAuthResponse(tokens, user));
    }

    // パスワードを忘れた場合、登録メールアドレス宛に6桁コードを送る。
    // メールアドレスの存在有無に関わらず常に同じレスポンスを返す（登録有無の推測を防ぐ）。
    [HttpPost("forgot-password")]
    public async Task<IActionResult> ForgotPassword(ForgotPasswordRequest request, CancellationToken ct)
    {
        var email = request.Email.Trim();
        var lockoutKey = $"forgot-password-lockout:{email.ToLowerInvariant()}";
        if (!_cache.TryGetValue(lockoutKey, out _))
        {
            _cache.Set(lockoutKey, true, TimeSpan.FromMinutes(1)); // 同一メールアドレスへの連続送信を抑制する

            var user = await _db.Users.FirstOrDefaultAsync(u => u.Email.ToLower() == email.ToLowerInvariant(), ct);
            if (user is not null && user.Status == "active")
            {
                var code = RandomNumberGenerator.GetInt32(0, 1_000_000).ToString("D6");
                _db.PasswordResetTokens.Add(new PasswordResetToken
                {
                    TokenId = Guid.NewGuid(),
                    UserId = user.UserId,
                    CodeHash = _hasher.Hash(code),
                    ExpiresAt = DateTimeOffset.UtcNow.Add(ResetCodeValidity),
                    CreatedAt = DateTimeOffset.UtcNow,
                });
                await _db.SaveChangesAsync(ct);

                try
                {
                    await _email.SendAsync(
                        user.Email,
                        "【GOEN】パスワード再設定コード",
                        $"パスワード再設定用のコードです。\n\n{code}\n\n" +
                        $"このコードは{(int)ResetCodeValidity.TotalMinutes}分間有効です。" +
                        "心当たりがない場合は本メールを破棄してください。",
                        ct);
                }
                catch (Exception ex)
                {
                    // メール送信に失敗しても、ユーザー列挙防止のため成功と同じレスポンスを返す
                    _logger.LogWarning(ex, "パスワードリセットメールの送信に失敗しました");
                }
            }
        }

        return Ok(new { message = "登録されているメールアドレスの場合、再設定用のコードを送信しました。" });
    }

    [HttpPost("reset-password")]
    public async Task<IActionResult> ResetPassword(ResetPasswordRequest request, CancellationToken ct)
    {
        if (request.NewPassword.Length < MinPasswordLength)
        {
            return BadRequest(new { message = $"パスワードは{MinPasswordLength}文字以上で設定してください。" });
        }

        var email = request.Email.Trim();
        var user = await _db.Users.FirstOrDefaultAsync(u => u.Email.ToLower() == email.ToLowerInvariant(), ct);
        if (user is null)
        {
            return BadRequest(new { message = "コードが正しくないか、有効期限が切れています。" });
        }

        var candidates = await _db.PasswordResetTokens
            .Where(t => t.UserId == user.UserId && t.UsedAt == null && t.ExpiresAt > DateTimeOffset.UtcNow)
            .OrderByDescending(t => t.CreatedAt)
            .ToListAsync(ct);

        var match = candidates.FirstOrDefault(t => _hasher.Verify(request.Code, t.CodeHash));
        if (match is null)
        {
            return BadRequest(new { message = "コードが正しくないか、有効期限が切れています。" });
        }

        match.UsedAt = DateTimeOffset.UtcNow;
        user.PasswordHash = _hasher.Hash(request.NewPassword);
        user.UpdatedBy = user.UserId;

        // 既存のリフレッシュトークンは全て失効させる（パスワード変更後は再ログインを必須にする）
        var activeTokens = await _db.AuthTokens.Where(t => t.UserId == user.UserId && t.RevokedAt == null).ToListAsync(ct);
        foreach (var token in activeTokens)
        {
            token.RevokedAt = DateTimeOffset.UtcNow;
        }

        await _db.SaveChangesAsync(ct);

        return Ok(new { message = "パスワードを再設定しました。新しいパスワードでログインしてください。" });
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
