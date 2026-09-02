using System.Security.Cryptography;
using Goen.Api.Dtos;
using Goen.Domain.Entities;
using Goen.Infrastructure.Billing;
using Goen.Infrastructure.Messaging;
using Goen.Infrastructure.Persistence;
using Goen.Infrastructure.Security;
using Microsoft.AspNetCore.Authorization;
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
    private readonly ISubscriptionService _subscription;
    private readonly ILogger<AuthController> _logger;

    public AuthController(
        GoenDbContext db, Pbkdf2PasswordHasher hasher, JwtTokenService tokenService, IMemoryCache cache,
        IEmailService email, ISubscriptionService subscription, ILogger<AuthController> logger)
    {
        _db = db;
        _hasher = hasher;
        _tokenService = tokenService;
        _cache = cache;
        _email = email;
        _subscription = subscription;
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

    // 設定画面: メールアドレス変更。本人確認のため現在のパスワードを必須にする。
    [Authorize]
    [HttpPut("email")]
    public async Task<IActionResult> ChangeEmail(ChangeEmailRequest request, CancellationToken ct)
    {
        var newEmail = request.NewEmail.Trim();
        if (string.IsNullOrWhiteSpace(newEmail) || !newEmail.Contains('@'))
        {
            return BadRequest(new { message = "正しいメールアドレスを入力してください。" });
        }

        var user = await _db.Users.FirstOrDefaultAsync(u => u.UserId == User.GetUserId(), ct);
        if (user is null) return NotFound();

        if (!_hasher.Verify(request.CurrentPassword, user.PasswordHash))
        {
            return Unauthorized(new { message = "現在のパスワードが正しくありません。" });
        }

        var exists = await _db.Users.AnyAsync(u => u.UserId != user.UserId && u.Email.ToLower() == newEmail.ToLowerInvariant(), ct);
        if (exists)
        {
            return Conflict(new { message = "このメールアドレスは既に使用されています。" });
        }

        var oldEmail = user.Email;
        user.Email = newEmail;
        user.UpdatedBy = user.UserId;
        await _db.SaveChangesAsync(ct);

        // 変更に心当たりがない場合に気づけるよう、旧アドレスへ通知する（送信失敗しても変更自体は成立させる）
        try
        {
            await _email.SendAsync(
                oldEmail,
                "【GOEN】メールアドレスが変更されました",
                $"アカウントのメールアドレスが {newEmail} に変更されました。\n\n" +
                "心当たりがない場合は、至急パスワードの再設定を行い、サポート窓口までご連絡ください。",
                ct);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "メールアドレス変更通知メールの送信に失敗しました");
        }

        return Ok(new { message = "メールアドレスを変更しました。" });
    }

    // 設定画面: パスワード変更（ログイン中に実施）。パスワードを忘れた場合のForgotPassword/ResetPasswordとは別フロー。
    [Authorize]
    [HttpPut("password")]
    public async Task<ActionResult<AuthResponse>> ChangePassword(ChangePasswordRequest request, CancellationToken ct)
    {
        if (request.NewPassword.Length < MinPasswordLength)
        {
            return BadRequest(new { message = $"新しいパスワードは{MinPasswordLength}文字以上で設定してください。" });
        }

        var user = await _db.Users.FirstOrDefaultAsync(u => u.UserId == User.GetUserId(), ct);
        if (user is null) return NotFound();

        if (!_hasher.Verify(request.CurrentPassword, user.PasswordHash))
        {
            return Unauthorized(new { message = "現在のパスワードが正しくありません。" });
        }

        user.PasswordHash = _hasher.Hash(request.NewPassword);
        user.UpdatedBy = user.UserId;

        // 他の端末・セッションの安全のため既存のリフレッシュトークンは全て失効させたうえで、
        // 今回のリクエスト（この端末）用に新しいトークンを発行し直し、再ログインなしで継続利用できるようにする。
        var activeTokens = await _db.AuthTokens.Where(t => t.UserId == user.UserId && t.RevokedAt == null).ToListAsync(ct);
        foreach (var token in activeTokens)
        {
            token.RevokedAt = DateTimeOffset.UtcNow;
        }

        var tokens = await IssueTokensAsync(user, ct);
        await _db.SaveChangesAsync(ct);

        try
        {
            await _email.SendAsync(
                user.Email,
                "【GOEN】パスワードが変更されました",
                "アカウントのパスワードが変更されました。心当たりがない場合は、至急サポート窓口までご連絡ください。",
                ct);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "パスワード変更通知メールの送信に失敗しました");
        }

        return Ok(ToAuthResponse(tokens, user));
    }

    // 設定画面: アカウント削除（退会）。本人確認のため現在のパスワードを必須にする。
    // GOENは「個人アカウント＝1組織」の設計のため、退会＝組織ごと削除する。
    // Appleガイドライン5.1.1(v)「アプリ内から削除を開始できること」に対応するための本格実装。
    [Authorize]
    [HttpDelete("me")]
    public async Task<IActionResult> DeleteAccount(DeleteAccountRequest request, CancellationToken ct)
    {
        var user = await _db.Users.FirstOrDefaultAsync(u => u.UserId == User.GetUserId(), ct);
        if (user is null) return NotFound();

        if (!_hasher.Verify(request.CurrentPassword, user.PasswordHash))
        {
            return Unauthorized(new { message = "現在のパスワードが正しくありません。" });
        }

        var orgId = user.OrgId;
        var email = user.Email;

        // Stripe解約は削除に付随する処理のため、失敗しても退会自体は続行する（ログのみ残す）。
        try
        {
            await _subscription.CancelSubscriptionAsync(orgId, ct);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "アカウント削除に伴うサブスク解約に失敗しました orgId={OrgId}", orgId);
        }

        // 「個人アカウント＝1組織」の設計上、組織配下のデータを全て削除すればアカウント削除になる。
        // persons削除はperson_profiles/person_tags/person_relations/next_actions/ai_person_cards/
        // person_research_results/contacts(→contact_media/transcripts)/intro_letter_requests/rag_chunks/
        // persons_readへON DELETE CASCADEで連鎖する（db/ddl_goen_v1.0.sql参照）。
        // それ以外の「personsを参照するがCASCADE指定のないテーブル」は先に個別クリーンアップする。
        await using var tx = await _db.Database.BeginTransactionAsync(ct);
        try
        {
            await _db.Database.ExecuteSqlInterpolatedAsync(
                $"UPDATE persons SET introducer_person_id = NULL WHERE org_id = {orgId} AND introducer_person_id IS NOT NULL", ct);
            await _db.Database.ExecuteSqlInterpolatedAsync(
                $"""
                DELETE FROM referral_needs
                WHERE person_id IN (SELECT person_id FROM persons WHERE org_id = {orgId})
                   OR user_id IN (SELECT user_id FROM users WHERE org_id = {orgId})
                """, ct);
            await _db.Database.ExecuteSqlInterpolatedAsync(
                $"""
                DELETE FROM referrals
                WHERE from_user_id IN (SELECT user_id FROM users WHERE org_id = {orgId})
                   OR to_person_id IN (SELECT person_id FROM persons WHERE org_id = {orgId})
                   OR target_person_id IN (SELECT person_id FROM persons WHERE org_id = {orgId})
                """, ct);
            await _db.Database.ExecuteSqlInterpolatedAsync(
                $"DELETE FROM ai_assistant_queries WHERE org_id = {orgId}", ct);
            await _db.Database.ExecuteSqlInterpolatedAsync(
                $"DELETE FROM tags WHERE org_id = {orgId}", ct);
            await _db.Database.ExecuteSqlInterpolatedAsync(
                $"DELETE FROM import_jobs WHERE org_id = {orgId}", ct);
            await _db.Database.ExecuteSqlInterpolatedAsync(
                $"DELETE FROM persons WHERE org_id = {orgId}", ct);
            await _db.Database.ExecuteSqlInterpolatedAsync(
                $"DELETE FROM users WHERE org_id = {orgId}", ct);
            await _db.Database.ExecuteSqlInterpolatedAsync(
                $"DELETE FROM organizations WHERE org_id = {orgId}", ct);

            await tx.CommitAsync(ct);
        }
        catch
        {
            await tx.RollbackAsync(ct);
            throw;
        }

        _logger.LogInformation("アカウントが削除されました email={Email} orgId={OrgId}", email, orgId);
        return Ok(new { message = "アカウントを削除しました。" });
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
