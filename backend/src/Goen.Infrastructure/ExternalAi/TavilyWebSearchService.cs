using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json.Serialization;
using Microsoft.Extensions.Options;

namespace Goen.Infrastructure.ExternalAi;

// F-038 AI自動リサーチのWeb検索（I-006）。Tavily Search API（POST https://api.tavily.com/search）を使用する。
// AIエージェント向けに設計された検索APIで、結果がタイトル・URL・抜粋の形で返るためLLMへの入力に適している。
public class TavilyWebSearchService : IWebSearchService
{
    private readonly HttpClient _http;

    public TavilyWebSearchService(HttpClient http, IOptions<WebSearchOptions> options)
    {
        http.BaseAddress = new Uri("https://api.tavily.com/");
        http.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", options.Value.ApiKey);
        _http = http;
    }

    public async Task<IReadOnlyList<WebSearchResult>> SearchAsync(
        string query, int maxResults, CancellationToken cancellationToken = default)
    {
        var request = new TavilySearchRequest(query, Math.Clamp(maxResults, 1, 20));
        using var response = await _http.PostAsJsonAsync("search", request, cancellationToken);
        response.EnsureSuccessStatusCode();

        var body = await response.Content.ReadFromJsonAsync<TavilySearchResponse>(cancellationToken: cancellationToken)
            ?? throw new InvalidOperationException("Tavily APIから空の応答が返却されました。");

        return body.Results
            .Select(r => new WebSearchResult(r.Title, r.Url, r.Content))
            .ToList();
    }

    private record TavilySearchRequest(
        string Query,
        [property: JsonPropertyName("max_results")] int MaxResults);

    private record TavilySearchResponse(TavilyResult[] Results);

    private record TavilyResult(string Title, string Url, string Content);
}
