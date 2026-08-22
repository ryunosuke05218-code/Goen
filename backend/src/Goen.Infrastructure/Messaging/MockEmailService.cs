using Microsoft.Extensions.Logging;

namespace Goen.Infrastructure.Messaging;

// メール配信サービス（SendGrid等）未接続の開発環境向けダミー実装。実際には送信せずログへ出力する。
// パスワードリセットの6桁コード等をここで確認できるため、開発中はメール配信サービスが無くても
// 動作確認できる（AIプロバイダのmock実装と同じ考え方）。
public class MockEmailService : IEmailService
{
    private readonly ILogger<MockEmailService> _logger;

    public MockEmailService(ILogger<MockEmailService> logger)
    {
        _logger = logger;
    }

    public Task SendAsync(string toEmail, string subject, string bodyText, CancellationToken cancellationToken = default)
    {
        _logger.LogInformation(
            "[MockEmailService] メール送信（実際には送信されません）\n宛先: {ToEmail}\n件名: {Subject}\n本文:\n{Body}",
            toEmail, subject, bodyText);
        return Task.CompletedTask;
    }
}
