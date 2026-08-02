using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json.Serialization;
using Microsoft.Extensions.Options;

namespace Goen.Infrastructure.ExternalAi;

// OpenAI互換の /v1/embeddings エンドポイントを話すプロバイダなら何でも使える汎用実装。
// Ollama（multilingual-e5等）・OpenAI（text-embedding-3-small等）はいずれもこの形式に対応しているため、
// appsettings/User Secretsの Ai:Embedding:BaseUrl / Model / ApiKey / 各種Prefixを差し替えるだけで
// プロバイダを切り替えられる（Program.cs側のコード変更は不要）。
// 注意: Ollama公式ドキュメントでは /v1/embeddings は実験的サポートとされており、将来仕様が変わる可能性がある。
public class OpenAiCompatibleEmbeddingService : IEmbeddingService
{
    private readonly HttpClient _http;
    private readonly AiEmbeddingOptions _options;

    public OpenAiCompatibleEmbeddingService(HttpClient http, IOptions<AiEmbeddingOptions> options)
    {
        _options = options.Value;
        http.BaseAddress = new Uri(_options.BaseUrl.TrimEnd('/') + "/");
        http.DefaultRequestHeaders.Authorization =
            new AuthenticationHeaderValue("Bearer", string.IsNullOrWhiteSpace(_options.ApiKey) ? "unused" : _options.ApiKey);
        _http = http;
    }

    public Task<float[]> EmbedDocumentAsync(string text, CancellationToken cancellationToken = default) =>
        EmbedAsync(_options.DocumentPrefix + text, cancellationToken);

    public Task<float[]> EmbedQueryAsync(string text, CancellationToken cancellationToken = default) =>
        EmbedAsync(_options.QueryPrefix + text, cancellationToken);

    private async Task<float[]> EmbedAsync(string input, CancellationToken ct)
    {
        var request = new EmbeddingRequest(_options.Model, input);

        using var response = await _http.PostAsJsonAsync("embeddings", request, ct);
        response.EnsureSuccessStatusCode();

        var body = await response.Content.ReadFromJsonAsync<EmbeddingResponse>(cancellationToken: ct)
            ?? throw new InvalidOperationException($"{_options.Provider} embeddings APIから空の応答が返却されました。");

        var vector = body.Data.FirstOrDefault()?.Embedding
            ?? throw new InvalidOperationException($"{_options.Provider} embeddings APIの応答にembeddingが含まれていません。");

        if (vector.Length != _options.Dimension)
        {
            throw new InvalidOperationException(
                $"埋め込みの次元数が設定と一致しません（期待値: {_options.Dimension}、実際: {vector.Length}）。" +
                "Ai:Embedding:Model と Ai:Embedding:Dimension の組み合わせを確認してください。");
        }

        return vector;
    }

    private record EmbeddingRequest(string Model, string Input);

    private record EmbeddingResponse(EmbeddingData[] Data);

    private record EmbeddingData([property: JsonPropertyName("embedding")] float[] Embedding);
}
