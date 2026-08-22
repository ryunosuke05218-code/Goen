namespace Goen.Api.Dtos;

public record LoginRequest(string Email, string Password);

public record RefreshRequest(string RefreshToken);

public record AuthResponse(
    string AccessToken,
    DateTimeOffset AccessTokenExpiresAt,
    string RefreshToken,
    DateTimeOffset RefreshTokenExpiresAt,
    UserSummary User);

public record UserSummary(Guid UserId, string Email, string DisplayName, string Role);

// 自己登録: 新規登録者ごとに新しい組織（personal）を作成し、その最初のユーザーとして登録する
public record RegisterRequest(string Email, string Password, string DisplayName);

// パスワードリセット: メールで送る6桁コードで本人確認する（モバイルアプリのためディープリンクより簡単な方式）
public record ForgotPasswordRequest(string Email);

public record ResetPasswordRequest(string Email, string Code, string NewPassword);
