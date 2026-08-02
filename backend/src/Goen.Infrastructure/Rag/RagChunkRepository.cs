using Goen.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Npgsql;

namespace Goen.Infrastructure.Rag;

public record RagSearchHit(Guid PersonId, Guid ChunkId, string SourceType, string Content, double Score);

// rag_chunks への書き込み・検索。pgvectorへのアクセスは追加パッケージを使わず、
// ベクトルをテキストリテラルにフォーマットして "::vector" キャストする方式で行う（PgVectorFormat参照）。
public class RagChunkRepository
{
    private readonly GoenDbContext _db;

    public RagChunkRepository(GoenDbContext db)
    {
        _db = db;
    }

    // 指定ソースの既存チャンクを全削除してから新しいチャンク群を挿入する（差分更新はせず単純化する）。
    public async Task ReplaceChunksAsync(
        string sourceType, Guid sourceId, Guid personId, Guid orgId, Guid ownerUserId, string visibility,
        string? industryCode, string? prefCode, string embeddingModel, int embeddingDim,
        IReadOnlyList<(RagChunkDraft Draft, float[] Embedding)> chunks, CancellationToken ct)
    {
        var (conn, shouldClose) = await AcquireConnectionAsync(ct);
        await using var tx = await conn.BeginTransactionAsync(ct);
        try
        {
            await using (var del = new NpgsqlCommand(
                "DELETE FROM rag_chunks WHERE source_type = @source_type AND source_id = @source_id", conn, tx))
            {
                del.Parameters.AddWithValue("source_type", sourceType);
                del.Parameters.AddWithValue("source_id", sourceId);
                await del.ExecuteNonQueryAsync(ct);
            }

            foreach (var (draft, embedding) in chunks)
            {
                const string sql = """
                    INSERT INTO rag_chunks (
                        chunk_id, org_id, owner_user_id, person_id, visibility, source_type, source_id,
                        source_version, chunk_no, content, embedding, embedding_model, embedding_dim,
                        occurred_at, industry_code, pref_code, token_count, created_at
                    ) VALUES (
                        gen_random_uuid(), @org_id, @owner_user_id, @person_id, @visibility, @source_type, @source_id,
                        @source_version, @chunk_no, @content, @embedding::vector, @embedding_model, @embedding_dim,
                        @occurred_at, @industry_code, @pref_code, @token_count, now()
                    );
                    """;
                await using var cmd = new NpgsqlCommand(sql, conn, tx);
                cmd.Parameters.AddWithValue("org_id", orgId);
                cmd.Parameters.AddWithValue("owner_user_id", ownerUserId);
                cmd.Parameters.AddWithValue("person_id", personId);
                cmd.Parameters.AddWithValue("visibility", visibility);
                cmd.Parameters.AddWithValue("source_type", sourceType);
                cmd.Parameters.AddWithValue("source_id", sourceId);
                cmd.Parameters.AddWithValue("source_version", draft.SourceVersion);
                cmd.Parameters.AddWithValue("chunk_no", draft.ChunkNo);
                cmd.Parameters.AddWithValue("content", draft.Content);
                cmd.Parameters.AddWithValue("embedding", PgVectorFormat.ToLiteral(embedding));
                cmd.Parameters.AddWithValue("embedding_model", embeddingModel);
                cmd.Parameters.AddWithValue("embedding_dim", embeddingDim);
                cmd.Parameters.AddWithValue("occurred_at", (object?)draft.OccurredAt ?? DBNull.Value);
                cmd.Parameters.AddWithValue("industry_code", (object?)industryCode ?? DBNull.Value);
                cmd.Parameters.AddWithValue("pref_code", (object?)prefCode ?? DBNull.Value);
                cmd.Parameters.AddWithValue("token_count", draft.Content.Length / 2); // 目安値（正確なトークナイズは行わない）
                await cmd.ExecuteNonQueryAsync(ct);
            }

            await tx.CommitAsync(ct);
        }
        catch
        {
            await tx.RollbackAsync(ct);
            throw;
        }
        finally
        {
            if (shouldClose) await conn.CloseAsync();
        }
    }

    public async Task DeleteBySourceAsync(string sourceType, Guid sourceId, CancellationToken ct)
    {
        var (conn, shouldClose) = await AcquireConnectionAsync(ct);
        try
        {
            await using var cmd = new NpgsqlCommand(
                "DELETE FROM rag_chunks WHERE source_type = @source_type AND source_id = @source_id", conn);
            cmd.Parameters.AddWithValue("source_type", sourceType);
            cmd.Parameters.AddWithValue("source_id", sourceId);
            await cmd.ExecuteNonQueryAsync(ct);
        }
        finally
        {
            if (shouldClose) await conn.CloseAsync();
        }
    }

    public async Task DeleteAllForPersonAsync(Guid personId, CancellationToken ct)
    {
        var (conn, shouldClose) = await AcquireConnectionAsync(ct);
        try
        {
            await using var cmd = new NpgsqlCommand("DELETE FROM rag_chunks WHERE person_id = @person_id", conn);
            cmd.Parameters.AddWithValue("person_id", personId);
            await cmd.ExecuteNonQueryAsync(ct);
        }
        finally
        {
            if (shouldClose) await conn.CloseAsync();
        }
    }

    // AI人物カルテは世代ごとにcard_id（source_id）が変わるため、最新以外のカルテ由来チャンクを掃除する
    public async Task DeleteSupersededCardChunksAsync(Guid personId, Guid currentCardId, CancellationToken ct)
    {
        var (conn, shouldClose) = await AcquireConnectionAsync(ct);
        try
        {
            await using var cmd = new NpgsqlCommand(
                "DELETE FROM rag_chunks WHERE source_type = 'card' AND person_id = @person_id AND source_id <> @card_id",
                conn);
            cmd.Parameters.AddWithValue("person_id", personId);
            cmd.Parameters.AddWithValue("card_id", currentCardId);
            await cmd.ExecuteNonQueryAsync(ct);
        }
        finally
        {
            if (shouldClose) await conn.CloseAsync();
        }
    }

    // ハイブリッド検索（ベクトル + 全文/トライグラム類似）をRRF（Reciprocal Rank Fusion）で統合する。
    // テーブル設計書 9.1 のSQLを踏襲。
    public async Task<List<RagSearchHit>> SearchAsync(
        Guid ownerUserId, float[] queryEmbedding, string queryText, int limit, CancellationToken ct)
    {
        var (conn, shouldClose) = await AcquireConnectionAsync(ct);
        try
        {
            const string sql = """
                WITH vec AS (
                    SELECT chunk_id, person_id, source_type, content,
                           ROW_NUMBER() OVER (ORDER BY embedding <=> @query_vec::vector) AS rnk
                    FROM rag_chunks
                    WHERE owner_user_id = @owner_user_id
                    ORDER BY embedding <=> @query_vec::vector
                    LIMIT 50
                ),
                txt AS (
                    SELECT chunk_id, person_id, source_type, content,
                           ROW_NUMBER() OVER (ORDER BY similarity(content, @query_text) DESC) AS rnk
                    FROM rag_chunks
                    WHERE owner_user_id = @owner_user_id AND content % @query_text
                    LIMIT 50
                ),
                fused AS (
                    SELECT chunk_id, person_id, source_type, content, SUM(1.0 / (60 + rnk)) AS score
                    FROM (SELECT * FROM vec UNION ALL SELECT * FROM txt) u
                    GROUP BY chunk_id, person_id, source_type, content
                )
                SELECT chunk_id, person_id, source_type, content, score
                FROM fused
                ORDER BY score DESC
                LIMIT @limit;
                """;
            await using var cmd = new NpgsqlCommand(sql, conn);
            cmd.Parameters.AddWithValue("owner_user_id", ownerUserId);
            cmd.Parameters.AddWithValue("query_vec", PgVectorFormat.ToLiteral(queryEmbedding));
            cmd.Parameters.AddWithValue("query_text", queryText);
            cmd.Parameters.AddWithValue("limit", limit);

            var result = new List<RagSearchHit>();
            await using var reader = await cmd.ExecuteReaderAsync(ct);
            while (await reader.ReadAsync(ct))
            {
                result.Add(new RagSearchHit(
                    reader.GetGuid(1), reader.GetGuid(0), reader.GetString(2), reader.GetString(3), reader.GetDouble(4)));
            }
            return result;
        }
        finally
        {
            if (shouldClose) await conn.CloseAsync();
        }
    }

    private async Task<(NpgsqlConnection conn, bool shouldClose)> AcquireConnectionAsync(CancellationToken ct)
    {
        var conn = (NpgsqlConnection)_db.Database.GetDbConnection();
        var shouldClose = conn.State != System.Data.ConnectionState.Open;
        if (shouldClose)
        {
            await conn.OpenAsync(ct);
        }
        return (conn, shouldClose);
    }
}
