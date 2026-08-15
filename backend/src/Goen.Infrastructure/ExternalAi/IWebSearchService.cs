namespace Goen.Infrastructure.ExternalAi;

// F-038 AI自動リサーチの検索結果（タイトル・URL・抜粋）。出典としてそのままUIへ表示する。
public record WebSearchResult(string Title, string Url, string Snippet);

// F-038向けのWeb検索（要件I-006）。プロバイダ未選定のため、実装はMockWebSearchServiceのみ提供する。
public interface IWebSearchService
{
    Task<IReadOnlyList<WebSearchResult>> SearchAsync(string query, int maxResults, CancellationToken cancellationToken = default);
}
