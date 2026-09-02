namespace Goen.Infrastructure.Billing;

// サブスク課金の状態（決済プロバイダに依存しない内部表現）。
public record SubscriptionStatus(
    string Status, // trialing / active / past_due / canceled / incomplete
    string? Provider, // stripe / google_play / app_store
    string? PlanCode,
    DateTimeOffset? CurrentPeriodEnd,
    DateTimeOffset? TrialEndsAt);

// チェックアウト（新規契約）・カスタマーポータル（契約管理）への遷移先URL。
// Stripeはホスト型ページのURLを返す。将来Google Play/App StoreのIAPを追加する場合、
// 決済フロー自体がアプリ内で完結する（ブラウザ遷移が不要）ため、実装によっては
// PortalUrl等がnullになりうる想定でモバイル側はnullチェックする。
public record CheckoutSession(string Url);
public record BillingPortalSession(string Url);

// サブスク課金（要件: サブスクでの運用）。決済手段はStripeを想定して開発するが、
// App Store/Google Playでの配布時はストアのIAP（アプリ内課金）使用が規約上必須となるため、
// 本インターフェースは特定の決済プロバイダに依存しない形にしてある。
// 将来 GooglePlaySubscriptionService / AppStoreSubscriptionService を追加する際も、
// 呼び出し側（BillingController等）のコードは変更不要にすることを狙いとする。
public interface ISubscriptionService
{
    Task<SubscriptionStatus> GetStatusAsync(Guid orgId, CancellationToken cancellationToken = default);

    // 新規契約用のチェックアウトへの遷移先を作成する。IAP実装ではアプリ内購入フローを直接起動するため
    // 別のAPI形状になる可能性があり、その場合は本メソッドを使わないモバイル側の分岐が必要になる。
    Task<CheckoutSession> CreateCheckoutSessionAsync(Guid orgId, string planCode, CancellationToken cancellationToken = default);

    // 契約内容の変更・解約等を行うポータルへの遷移先を作成する（Stripeのカスタマーポータル等）。
    Task<BillingPortalSession> CreateBillingPortalSessionAsync(Guid orgId, CancellationToken cancellationToken = default);

    // アカウント削除時に即時解約する。カスタマーポータルへ誘導する余地のない「その場で退会」フロー用。
    // 未契約（契約IDが無い）組織に対しては何もしない。
    Task CancelSubscriptionAsync(Guid orgId, CancellationToken cancellationToken = default);
}
