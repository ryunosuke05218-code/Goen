namespace Goen.Infrastructure.ExternalAi;

// 埋め込み(embedding)プロバイダ設定。OllamaとOpenAIはいずれもOpenAI互換の /v1/embeddings
// エンドポイントを提供するため、BaseUrl・Model・ApiKeyを差し替えるだけでプロバイダを切り替えられる。
//
// 重要: 埋め込みモデルを切り替えると出力ベクトルの次元数・ベクトル空間が変わるため、
// チャットモデルの切替とは異なり「設定変更だけ」では済まない。既存の rag_chunks は再埋め込みが必要になる
// （db/ddl_goen_v1.0.sql 4.4節・migrations/0001 のコメント参照）。
//
// QueryPrefix / DocumentPrefix: multilingual-e5系のモデルは検索クエリ・被検索文書それぞれに
// "query: " / "passage: " という接頭辞を付けることを前提に学習されており、付けないと検索精度が落ちる。
// OpenAIの text-embedding-3-small 等ではこの接頭辞は不要なため空文字を設定する。
public class AiEmbeddingOptions
{
    public const string SectionName = "Ai:Embedding";

    public string Provider { get; set; } = "mock"; // mock / ollama / openai
    public string BaseUrl { get; set; } = "http://localhost:11434/v1";
    public string Model { get; set; } = "jeffh/intfloat-multilingual-e5-large-instruct:q8_0"; // タグ省略不可（:latestは存在しない）
    public string ApiKey { get; set; } = "";
    public int Dimension { get; set; } = 1024;
    public string QueryPrefix { get; set; } = "query: ";
    public string DocumentPrefix { get; set; } = "passage: ";
}
