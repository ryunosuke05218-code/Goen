namespace Goen.Infrastructure.Rag;

// RAGチャンク化の結果1件分。RagIndexingWorkerがこれを埋め込み生成してrag_chunksへ書き込む。
public record RagChunkDraft(
    int ChunkNo,
    string Content,
    int SourceVersion,
    DateTimeOffset? OccurredAt);
