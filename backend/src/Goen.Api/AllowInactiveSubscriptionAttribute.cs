namespace Goen.Api;

// SubscriptionGateFilterの対象から除外するためのマーカー属性。
// 認証・課金まわり（ログイン・契約状況の確認/決済セッション発行・Webhook受信）は、
// サブスク未契約・期限切れの状態でも必ず動作しなければならないため、これらのコントローラに付与する。
[AttributeUsage(AttributeTargets.Class | AttributeTargets.Method)]
public class AllowInactiveSubscriptionAttribute : Attribute
{
}
