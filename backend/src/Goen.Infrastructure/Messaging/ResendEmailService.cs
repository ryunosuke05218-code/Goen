using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json.Serialization;
using Microsoft.Extensions.Options;

namespace Goen.Infrastructure.Messaging;

// パスワードリセット等のトランザクションメール送信。Resend API
// （POST https://api.resend.com/emails）をHTTPで直接呼び出す（他の外部連携と同様、
// 専用SDKは使わずHttpClientのみで完結させ、依存を増やさない）。
// Resendは月3,000通/日100通までの無料枠が期限なしで使える（SendGridは60日トライアルのみ）。
public class ResendEmailService : IEmailService
{
    private readonly HttpClient _http;
    private readonly EmailOptions _options;

    public ResendEmailService(HttpClient http, IOptions<EmailOptions> options)
    {
        _options = options.Value;
        http.BaseAddress = new Uri("https://api.resend.com/");
        http.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", _options.ApiKey);
        _http = http;
    }

    public async Task SendAsync(string toEmail, string subject, string bodyText, CancellationToken cancellationToken = default)
    {
        var request = new ResendMailRequest(
            From: $"{_options.FromName} <{_options.FromEmail}>",
            To: new[] { toEmail },
            Subject: subject,
            Text: bodyText);

        using var response = await _http.PostAsJsonAsync("emails", request, cancellationToken);
        if (!response.IsSuccessStatusCode)
        {
            var body = await response.Content.ReadAsStringAsync(cancellationToken);
            throw new InvalidOperationException($"Resend APIへのメール送信に失敗しました（{(int)response.StatusCode}）: {body}");
        }
    }

    private record ResendMailRequest(
        [property: JsonPropertyName("from")] string From,
        [property: JsonPropertyName("to")] string[] To,
        [property: JsonPropertyName("subject")] string Subject,
        [property: JsonPropertyName("text")] string Text);
}
