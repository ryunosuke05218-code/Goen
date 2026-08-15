namespace Goen.Infrastructure.ExternalAi;

// Web検索API（I-006）未選定のため、開発用のダミー実装を提供する。
// 常に0件を返す：存在しない検索結果をでっち上げるとF-038の「検索結果にない事実は創作しない」という
// 方針そのものを開発環境で検証できなくなるため、ダミーでも実データが無い状態を正直に返す。
public class MockWebSearchService : IWebSearchService
{
    public Task<IReadOnlyList<WebSearchResult>> SearchAsync(
        string query, int maxResults, CancellationToken cancellationToken = default)
        => Task.FromResult<IReadOnlyList<WebSearchResult>>(Array.Empty<WebSearchResult>());
}
