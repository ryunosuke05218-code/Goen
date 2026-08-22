namespace Goen.Api.Dtos;

public record SubscriptionStatusResponse(
    string Status,
    string? Provider,
    string? PlanCode,
    DateTimeOffset? CurrentPeriodEnd,
    DateTimeOffset? TrialEndsAt);

public record CreateCheckoutRequest(string PlanCode);

// Url が空文字の場合、モバイル側はブラウザを開かず契約状態を再取得するだけでよい
// （モック実装がAPIキー無しでも動作確認できるよう即座に契約完了とみなす挙動のため）。
public record CheckoutSessionResponse(string Url);

public record BillingPortalSessionResponse(string Url);
