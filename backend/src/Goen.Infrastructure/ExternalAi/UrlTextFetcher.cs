using System.Net;
using System.Net.Http;
using System.Text.RegularExpressions;

namespace Goen.Infrastructure.ExternalAi;

// HPリンク等の外部URLから本文テキストのみを抽出する共通ヘルパー。
// F-010（AIカルテ生成）・F-026（紹介文作成）など、HPリンクをAIの入力に含める機能から共通利用する。
public class UrlTextFetcher
{
    private readonly IHttpClientFactory _httpClientFactory;

    public UrlTextFetcher(IHttpClientFactory httpClientFactory)
    {
        _httpClientFactory = httpClientFactory;
    }

    // 取得・パースに失敗した場合はnullを返す。呼び出し元は他の情報のみで処理を続行する想定。
    public async Task<string?> TryFetchTextAsync(string url, CancellationToken ct)
    {
        if (!Uri.TryCreate(url, UriKind.Absolute, out var uri) || (uri.Scheme != "http" && uri.Scheme != "https"))
        {
            return null;
        }

        try
        {
            var client = _httpClientFactory.CreateClient();
            client.Timeout = TimeSpan.FromSeconds(10);
            client.DefaultRequestHeaders.UserAgent.ParseAdd("Mozilla/5.0 (compatible; GoenBot/1.0)");

            var html = await client.GetStringAsync(uri, ct);
            var text = Regex.Replace(html, "<script[^>]*>.*?</script>", " ",
                RegexOptions.Singleline | RegexOptions.IgnoreCase);
            text = Regex.Replace(text, "<style[^>]*>.*?</style>", " ",
                RegexOptions.Singleline | RegexOptions.IgnoreCase);
            text = Regex.Replace(text, "<[^>]+>", " ");
            text = WebUtility.HtmlDecode(text);
            text = Regex.Replace(text, @"\s+", " ").Trim();

            // プロンプトが肥大化しすぎないよう、本文は先頭3000文字程度に丸める
            return text.Length > 3000 ? text[..3000] : text;
        }
        catch
        {
            return null;
        }
    }
}
