namespace Goen.Infrastructure.Messaging;

// メール送信プロバイダ設定。
// 例:
//   開発（mock）: Provider=mock（コンソール/ログへ出力するのみ、実送信しない）
//   本番（Resend）: Provider=resend, ApiKey=実キー, FromEmail=送信元メールアドレス, FromName=表示名
//     ※Resendは月3,000通/日100通までの無料枠が期限なしで使える（推奨）
//   本番（SendGrid）: Provider=sendgrid, ApiKey=実キー, FromEmail=送信元メールアドレス, FromName=表示名
//     ※SendGridは60日間トライアル後は有料必須
// ApiKeyは appsettings に直接書かず、必ず dotnet user-secrets または環境変数で設定すること。
public class EmailOptions
{
    public const string SectionName = "Email";

    public string Provider { get; set; } = "mock"; // mock / resend / sendgrid
    public string ApiKey { get; set; } = "";
    public string FromEmail { get; set; } = "no-reply@goen.example.com";
    public string FromName { get; set; } = "GOEN";
}
