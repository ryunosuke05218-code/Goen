namespace Goen.Infrastructure.Billing;

// サブスク課金プロバイダ設定。開発中はStripeを使うが、Google Play/App Store配布時はOSのIAPへの
// 切替が規約上必要になるため、Providerの値を変えるだけで実装を切り替えられる構成にしてある。
// ApiKey・WebhookSecretは appsettings に直接書かず、必ず dotnet user-secrets または環境変数で設定すること。
public class SubscriptionOptions
{
    public const string SectionName = "Subscription";

    public string Provider { get; set; } = "mock"; // mock / stripe
    public string ApiKey { get; set; } = "";
    public string WebhookSecret { get; set; } = "";

    // Stripe Checkout完了後・キャンセル時・カスタマーポータルから戻る際の遷移先。
    // モバイルアプリ側にはWebフロントが無いため、当面は簡易な案内ページ等のURLを想定する
    // （将来的にはアプリのカスタムURLスキームへのディープリンクに置き換えて、決済完了後
    // 自動的にアプリへ戻れるようにする拡張余地を残す）。
    public string SuccessUrl { get; set; } = "https://example.com/billing/success";
    public string CancelUrl { get; set; } = "https://example.com/billing/cancel";
    public string PortalReturnUrl { get; set; } = "https://example.com/billing/return";

    // GOEN内部のプランコード（organizations.subscription_plan_code）→ StripeのPrice ID の対応表。
    // 例: {"standard_monthly": "price_xxxxx"}
    public Dictionary<string, string> PlanPriceIds { get; set; } = new();
}
