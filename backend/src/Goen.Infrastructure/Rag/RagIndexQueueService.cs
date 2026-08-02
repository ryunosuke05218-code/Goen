using Goen.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Npgsql;

namespace Goen.Infrastructure.Rag;

public record RagQueueItem(Guid QueueId, string SourceType, Guid SourceId, Guid PersonId, char Operation, int RetryCount);

// rag_index_queue への投入・取得を担当する。埋め込み生成（外部AI呼び出し）を保存操作の外に出し、
// ユーザーの保存操作をブロックしないようにする（テーブル設計書4.1）。
public class RagIndexQueueService
{
    private readonly GoenDbContext _db;

    public RagIndexQueueService(GoenDbContext db)
    {
        _db = db;
    }

    public async Task EnqueueAsync(string sourceType, Guid sourceId, Guid personId, char operation, CancellationToken ct)
    {
        var (conn, shouldClose) = await AcquireConnectionAsync(ct);
        try
        {
            const string sql = """
                INSERT INTO rag_index_queue (queue_id, source_type, source_id, person_id, operation, status, retry_count, enqueued_at)
                VALUES (gen_random_uuid(), @source_type, @source_id, @person_id, @operation, 'pending', 0, now())
                ON CONFLICT (source_type, source_id) WHERE status = 'pending' DO NOTHING;
                """;
            await using var cmd = new NpgsqlCommand(sql, conn);
            cmd.Parameters.AddWithValue("source_type", sourceType);
            cmd.Parameters.AddWithValue("source_id", sourceId);
            cmd.Parameters.AddWithValue("person_id", personId);
            cmd.Parameters.AddWithValue("operation", operation.ToString());
            await cmd.ExecuteNonQueryAsync(ct);
        }
        finally
        {
            if (shouldClose) await conn.CloseAsync();
        }
    }

    // 人物削除時: 残っているチャンクをすべて削除対象としてキューへ積む
    public Task EnqueuePersonDeletedAsync(Guid personId, CancellationToken ct) =>
        EnqueueAsync("profile", personId, personId, 'D', ct);

    public async Task<List<RagQueueItem>> ClaimBatchAsync(int batchSize, CancellationToken ct)
    {
        var (conn, shouldClose) = await AcquireConnectionAsync(ct);
        try
        {
            const string sql = """
                WITH next_batch AS (
                    SELECT queue_id FROM rag_index_queue
                    WHERE status = 'pending'
                    ORDER BY enqueued_at
                    LIMIT @batch_size
                    FOR UPDATE SKIP LOCKED
                )
                UPDATE rag_index_queue q
                SET status = 'processing', processed_at = now()
                FROM next_batch b
                WHERE q.queue_id = b.queue_id
                RETURNING q.queue_id, q.source_type, q.source_id, q.person_id, q.operation, q.retry_count;
                """;
            await using var cmd = new NpgsqlCommand(sql, conn);
            cmd.Parameters.AddWithValue("batch_size", batchSize);

            var result = new List<RagQueueItem>();
            await using var reader = await cmd.ExecuteReaderAsync(ct);
            while (await reader.ReadAsync(ct))
            {
                result.Add(new RagQueueItem(
                    reader.GetGuid(0), reader.GetString(1), reader.GetGuid(2), reader.GetGuid(3),
                    reader.GetString(4)[0], reader.GetInt32(5)));
            }
            return result;
        }
        finally
        {
            if (shouldClose) await conn.CloseAsync();
        }
    }

    public async Task MarkDoneAsync(Guid queueId, CancellationToken ct)
    {
        var (conn, shouldClose) = await AcquireConnectionAsync(ct);
        try
        {
            await using var cmd = new NpgsqlCommand(
                "UPDATE rag_index_queue SET status = 'done', processed_at = now() WHERE queue_id = @id", conn);
            cmd.Parameters.AddWithValue("id", queueId);
            await cmd.ExecuteNonQueryAsync(ct);
        }
        finally
        {
            if (shouldClose) await conn.CloseAsync();
        }
    }

    public async Task MarkFailedAsync(Guid queueId, int retryCount, string errorMessage, CancellationToken ct)
    {
        var (conn, shouldClose) = await AcquireConnectionAsync(ct);
        try
        {
            var status = retryCount >= 3 ? "failed" : "pending"; // 3回まで自動リトライする
            await using var cmd = new NpgsqlCommand(
                """
                UPDATE rag_index_queue
                SET status = @status, retry_count = @retry_count, error_message = @error, processed_at = now()
                WHERE queue_id = @id
                """, conn);
            cmd.Parameters.AddWithValue("status", status);
            cmd.Parameters.AddWithValue("retry_count", retryCount);
            cmd.Parameters.AddWithValue("error", errorMessage.Length > 2000 ? errorMessage[..2000] : errorMessage);
            cmd.Parameters.AddWithValue("id", queueId);
            await cmd.ExecuteNonQueryAsync(ct);
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
