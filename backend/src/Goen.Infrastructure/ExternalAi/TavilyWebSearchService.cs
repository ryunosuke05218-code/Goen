using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json.Serialization;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace Goen.Infrastructure.ExternalAi;

// F-038 AI自動リサーチのWeb検索（I-006）。Tavily Search API（POST https://api.tavily.com/search）を使用する。
// AIエージェント向けに設計された検索APIで、結果がタイトル・URL・抜粋の形で返るためLLMへの入力に適している。
public class TavilyWebSearchService : IWebSearchService
{
    private readonly HttpClient _http;
    private readonly ILogger<TavilyWebSearchService> _logger;

    public TavilyWebSearchService(HttpClient http, IOptions<WebSearchOptions> options, ILogger<TavilyWebSearchService> logger)
    {
        http.BaseAddress = new Uri("https://api.tavily.com/");
        http.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", options.Value.ApiKey);
        _http = http;
        _logger = logger;
    }

    public async Task<IReadOnlyList<WebSearchResult>> SearchAsync(
        string query, int maxResults, CancellationToken cancellationToken = default)
    {
        // search_depth=advanced: basic（既定）は速いが精度が低く、社名等の固有名詞検索では
        // 無関係なページ（同名の有名な別対象等）を拾いやすいため、精度優先のadvancedを使う。
        var request = new TavilySearchRequest(query, Math.Clamp(maxResults, 1, 20), "advanced");
        using var response = await _http.PostAsJsonAsync("search", request, cancellationToken);

        if (!response.IsSuccessStatusCode)
        {
            var errorBody = await response.Content.ReadAsStringAsync(cancellationToken);
            _logger.LogWarning("Tavily検索が失敗しました（{Status}）query={Query} body={Body}", response.StatusCode, query, errorBody);
            response.EnsureSuccessStatusCode();
        }

        var body = await response.Content.ReadFromJsonAsync<TavilySearchResponse>(cancellationToken: cancellationToken)
            ?? throw new InvalidOperationException("Tavily APIから空の応答が返却されました。");

        // 一時診断ログ: 実際に送ったクエリと返ってきたタイトル一覧を確認するため。
        _logger.LogInformation("Tavily検索結果 query=[{Query}] results=[{Titles}]",
            query, string.Join(" | ", body.Results.Select(r => r.Title)));

        return body.Results
            .Select(r => new WebSearchResult(r.Title, r.Url, r.Content))
            .ToList();
    }

    private record TavilySearchRequest(
        [property: JsonPropertyName("query")] string Query,
        [property: JsonPropertyName("max_results")] int MaxResults,
        [property: JsonPropertyName("search_depth")] string SearchDepth);

    private record TavilySearchResponse(TavilyResult[] Results);

    private record TavilyResult(string Title, string Url, string Content);
}
