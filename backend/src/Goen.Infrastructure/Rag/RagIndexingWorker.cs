using Goen.Infrastructure.ExternalAi;
using Goen.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace Goen.Infrastructure.Rag;

// rag_index_queue を定期的にポーリングし、埋め込み生成とrag_chunksへの反映を行うバックグラウンドワーカー。
// 保存操作（人物登録・接点記録等）を外部AI呼び出しでブロックしないためにキュー+非同期処理を採用する
// （テーブル設計書4.1）。
public class RagIndexingWorker : BackgroundService
{
    private static readonly TimeSpan IdleDelay = TimeSpan.FromSeconds(3);
    private static readonly TimeSpan ErrorDelay = TimeSpan.FromSeconds(5);
    private const int BatchSize = 5;

    private readonly IServiceScopeFactory _scopeFactory;
    private readonly ILogger<RagIndexingWorker> _logger;

    public RagIndexingWorker(IServiceScopeFactory scopeFactory, ILogger<RagIndexingWorker> logger)
    {
        _scopeFactory = scopeFactory;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            int processedCount;
            try
            {
                processedCount = await ProcessBatchAsync(stoppingToken);
            }
            catch (OperationCanceledException)
            {
                break;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "RAGインデックス処理でエラーが発生しました");
                await Task.Delay(ErrorDelay, stoppingToken);
                continue;
            }

            if (processedCount == 0)
            {
                await Task.Delay(IdleDelay, stoppingToken);
            }
        }
    }

    private async Task<int> ProcessBatchAsync(CancellationToken ct)
    {
        using var scope = _scopeFactory.CreateScope();
        var provider = scope.ServiceProvider;
        var queue = provider.GetRequiredService<RagIndexQueueService>();
        var chunkBuilder = provider.GetRequiredService<RagChunkBuilder>();
        var repository = provider.GetRequiredService<RagChunkRepository>();
        var embeddingService = provider.GetRequiredService<IEmbeddingService>();
        var embeddingOptions = provider.GetRequiredService<IOptions<AiEmbeddingOptions>>().Value;
        var db = provider.GetRequiredService<GoenDbContext>();

        var batch = await queue.ClaimBatchAsync(BatchSize, ct);

        foreach (var item in batch)
        {
            try
            {
                await ProcessItemAsync(item, db, chunkBuilder, repository, embeddingService, embeddingOptions, ct);
                await queue.MarkDoneAsync(item.QueueId, ct);
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "RAGチャンク更新に失敗しました（source_type={SourceType}, source_id={SourceId}）",
                    item.SourceType, item.SourceId);
                await queue.MarkFailedAsync(item.QueueId, item.RetryCount + 1, ex.Message, ct);
            }
        }

        return batch.Count;
    }

    private static async Task ProcessItemAsync(
        RagQueueItem item, GoenDbContext db, RagChunkBuilder chunkBuilder, RagChunkRepository repository,
        IEmbeddingService embeddingService, AiEmbeddingOptions embeddingOptions, CancellationToken ct)
    {
        if (item.Operation == 'D')
        {
            if (item.SourceType == "profile")
            {
                await repository.DeleteAllForPersonAsync(item.PersonId, ct);
            }
            else
            {
                await repository.DeleteBySourceAsync(item.SourceType, item.SourceId, ct);
            }
            return;
        }

        var drafts = await chunkBuilder.BuildAsync(item.SourceType, item.SourceId, item.PersonId, ct);
        if (drafts.Count == 0)
        {
            await repository.DeleteBySourceAsync(item.SourceType, item.SourceId, ct);
            return;
        }

        var meta = await db.Persons
            .Where(p => p.PersonId == item.PersonId)
            .Select(p => new { p.OrgId, p.OwnerUserId, p.Visibility, IndustryCode = p.Company != null ? p.Company.IndustryCode : null })
            .FirstOrDefaultAsync(ct);
        if (meta is null)
        {
            return; // 人物が既に削除済み
        }

        var prefCode = await db.PersonProfiles
            .Where(x => x.PersonId == item.PersonId)
            .Select(x => x.PrefCode)
            .FirstOrDefaultAsync(ct);

        var embedded = new List<(RagChunkDraft, float[])>(drafts.Count);
        foreach (var draft in drafts)
        {
            var vector = await embeddingService.EmbedDocumentAsync(draft.Content, ct);
            embedded.Add((draft, vector));
        }

        await repository.ReplaceChunksAsync(
            item.SourceType, item.SourceId, item.PersonId, meta.OrgId, meta.OwnerUserId, meta.Visibility,
            meta.IndustryCode, prefCode, embeddingOptions.Model, embeddingOptions.Dimension, embedded, ct);

        if (item.SourceType == "card")
        {
            await repository.DeleteSupersededCardChunksAsync(item.PersonId, item.SourceId, ct);
        }
    }
}
