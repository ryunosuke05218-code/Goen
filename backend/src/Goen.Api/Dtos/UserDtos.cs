namespace Goen.Api.Dtos;

public record UserSettingsResponse(
    Guid UserId,
    string Email,
    string DisplayName,
    bool AllowMutualRegistration,
    bool AllowNotifications);

// 表示名・F-028相互人脈登録・通知のON/OFF切替（設定画面）
public record UpdateUserSettingsRequest(string DisplayName, bool AllowMutualRegistration, bool AllowNotifications);

// F-027: 同一組織内の他ユーザー選択肢の取得
public record OrgMemberItem(Guid UserId, string DisplayName);

// 設定画面: メールアドレス変更（本人確認のため現在のパスワードを必須にする）
public record ChangeEmailRequest(string NewEmail, string CurrentPassword);

// 設定画面: パスワード変更（ログイン中に行う。パスワードを忘れた場合のフローとは別）
public record ChangePasswordRequest(string CurrentPassword, string NewPassword);
