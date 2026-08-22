namespace Goen.Infrastructure.Messaging;

// パスワードリセット等のトランザクションメール送信（要件Q-004拡張）。
// 他の外部AI連携（Ai:Chat等）と同じく、appsettings/User Secretsの Email:Provider を変えるだけで
// プロバイダを切り替えられるようにする（本番はSendGrid、将来的に他社へ切替可能）。
public interface IEmailService
{
    Task SendAsync(string toEmail, string subject, string bodyText, CancellationToken cancellationToken = default);
}
