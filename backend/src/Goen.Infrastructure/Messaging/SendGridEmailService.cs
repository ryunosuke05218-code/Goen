using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json.Serialization;
using Microsoft.Extensions.Options;

namespace Goen.Infrastructure.Messaging;

// パスワードリセット等のトランザクションメール送信。SendGrid v3 Mail Send API
// （POST https://api.sendgrid.com/v3/mail/send）をHTTPで直接呼び出す（他の外部連携と同様、
// 専用SDKは使わずHttpClientのみで完結させ、依存を増やさない）。
public class SendGridEmailService : IEmailService
{
    private readonly HttpClient _http;
    private readonly EmailOptions _options;

    public SendGridEmailService(HttpClient http, IOptions<EmailOptions> options)
    {
        _options = options.Value;
        http.BaseAddress = new Uri("https://api.sendgrid.com/v3/");
        http.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", _options.ApiKey);
        _http = http;
    }

    public async Task SendAsync(string toEmail, string subject, string bodyText, CancellationToken cancellationToken = default)
    {
        var request = new SendGridMailRequest(
            Personalizations: new[] { new SendGridPersonalization(new[] { new SendGridEmailAddress(toEmail) }) },
            From: new SendGridEmailAddress(_options.FromEmail, _options.FromName),
            Subject: subject,
            Content: new[] { new SendGridContent("text/plain", bodyText) });

        using var response = await _http.PostAsJsonAsync("mail/send", request, cancellationToken);
        if (!response.IsSuccessStatusCode)
        {
            var body = await response.Content.ReadAsStringAsync(cancellationToken);
            throw new InvalidOperationException($"SendGrid APIへのメール送信に失敗しました（{(int)response.StatusCode}）: {body}");
        }
    }

    private record SendGridMailRequest(
        SendGridPersonalization[] Personalizations,
        SendGridEmailAddress From,
        string Subject,
        SendGridContent[] Content);

    private record SendGridPersonalization(SendGridEmailAddress[] To);

    private record SendGridEmailAddress(string Email, string? Name = null);

    private record SendGridContent(string Type, string Value);
}
