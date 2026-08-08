namespace Goen.Api.Dtos;

public record UserSettingsResponse(
    Guid UserId,
    string Email,
    string DisplayName,
    bool AllowMutualRegistration);

// F-028: 相互人脈登録のON/OFF切替（設定画面）
public record UpdateUserSettingsRequest(bool AllowMutualRegistration);

// F-027: 同一組織内の他ユーザー選択肢の取得
public record OrgMemberItem(Guid UserId, string DisplayName);
