namespace Goen.Infrastructure.ExternalAi;

// RAG検索用の埋め込み(embedding)生成。EmbedDocumentAsync/EmbedQueryAsyncを分けているのは、
// multilingual-e5系のモデルが「検索対象文書」と「検索クエリ」で異なる接頭辞("passage: "/"query: ")を
// 前提に学習されているため（AiEmbeddingOptions.DocumentPrefix/QueryPrefix参照）。
// OpenAI等、接頭辞が不要なモデルでは両者は同じ結果になる。
public interface IEmbeddingService
{
    Task<float[]> EmbedDocumentAsync(string text, CancellationToken cancellationToken = default);

    Task<float[]> EmbedQueryAsync(string text, CancellationToken cancellationToken = default);
}
