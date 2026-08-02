using Microsoft.Extensions.Options;

namespace Goen.Infrastructure.ExternalAi;

// 埋め込みプロバイダ未接続時のダミー実装。意味的な類似度は再現できないが、
// 決定的（同じ文字列には毎回同じベクトルを返す）にすることでRAGパイプライン自体の動作確認はできるようにする。
public class MockEmbeddingService : IEmbeddingService
{
    private readonly int _dimension;

    public MockEmbeddingService(IOptions<AiEmbeddingOptions> options)
    {
        _dimension = options.Value.Dimension;
    }

    public Task<float[]> EmbedDocumentAsync(string text, CancellationToken cancellationToken = default) =>
        Task.FromResult(HashToVector(text));

    public Task<float[]> EmbedQueryAsync(string text, CancellationToken cancellationToken = default) =>
        Task.FromResult(HashToVector(text));

    private float[] HashToVector(string text)
    {
        var seed = text.Aggregate(17, (acc, c) => unchecked(acc * 31 + c));
        var random = new Random(seed);
        var vector = new float[_dimension];
        for (var i = 0; i < _dimension; i++)
        {
            vector[i] = (float)(random.NextDouble() * 2 - 1);
        }
        return vector;
    }
}
