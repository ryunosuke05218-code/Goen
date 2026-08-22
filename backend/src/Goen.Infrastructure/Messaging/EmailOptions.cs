namespace Goen.Infrastructure.Messaging;

// メール送信プロバイダ設定。
// 例:
//   開発（mock）: Provider=mock（コンソール/ログへ出力するのみ、実送信しない）
//   本番（SendGrid）: Provider=sendgrid, ApiKey=実キー, FromEmail=送信元メールアドレス, FromName=表示名
// ApiKeyは appsettings に直接書かず、必ず dotnet user-secrets または環境変数で設定すること。
public class EmailOptions
{
    public const string SectionName = "Email";

    public string Provider { get; set; } = "mock"; // mock / sendgrid
    public string ApiKey { get; set; } = "";
    public string FromEmail { get; set; } = "no-reply@goen.example.com";
    public string FromName { get; set; } = "GOEN";
}
