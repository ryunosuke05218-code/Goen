using Microsoft.EntityFrameworkCore;
using Npgsql;

namespace Goen.Infrastructure.Persistence;

public record NetworkNode(
    Guid PersonId, string FullName, string? CompanyName, string? IndustryName, string? OccupationName,
    int Depth, bool IsSelf = false);
public record NetworkEdge(Guid RelationId, Guid FromPersonId, Guid ToPersonId, string RelationType, int Strength);
public record NetworkGraph(IReadOnlyList<NetworkNode> Nodes, IReadOnlyList<NetworkEdge> Edges);

// F-005/F-006 人脈グラフ。テーブル設計書 5.3: 再帰CTEで距離2までを探索し、
// 表示情報は persons_read から一括取得する（結合1回）。
public class NetworkGraphService
{
    // 「自分」ノードを表す番兵ID。persons テーブルの実データとは衝突しない（アプリ生成UUIDのため）。
    public static readonly Guid SelfPersonId = Guid.Empty;

    private readonly GoenDbContext _db;

    public NetworkGraphService(GoenDbContext db)
    {
        _db = db;
    }

    // 自分を中心としたマインドマップ: 自分の直接の人脈(depth1)＋その人脈同士・二次接点(depth2)を返す。
    public async Task<NetworkGraph> GetMyNetworkAsync(
        Guid ownerUserId, Guid orgId, string ownerDisplayName,
        int depth1Limit = 25, int depth2Limit = 40, CancellationToken ct = default)
    {
        // 自分自身の人物カルテ（is_self）は人脈の連絡先ではないため、中心の「自分」ノード（selfNode、下記）とは
        // 別に通常の人脈として重複計上しない（ダッシュボードの集計と同じ方針）。
        var depth1 = await _db.PersonsRead
            .Where(r => r.OwnerUserId == ownerUserId && r.OrgId == orgId && !r.IsSelf)
            .OrderByDescending(r => r.LastContactAt)
            .Take(depth1Limit)
            .Select(r => new { r.PersonId, r.FullName, r.CompanyName, r.IndustryName, r.OccupationName })
            .ToListAsync(ct);

        var selfNode = new NetworkNode(SelfPersonId, ownerDisplayName, null, null, null, 0, true);

        if (depth1.Count == 0)
        {
            return new NetworkGraph(new[] { selfNode }, Array.Empty<NetworkEdge>());
        }

        var depth1Ids = depth1.Select(p => p.PersonId).ToHashSet();

        var conn = (NpgsqlConnection)_db.Database.GetDbConnection();
        var shouldClose = conn.State != System.Data.ConnectionState.Open;
        if (shouldClose)
        {
            await conn.OpenAsync(ct);
        }

        try
        {
            // 自分の人脈(depth1)に直接つながる関係を取得し、そこから二次接点(depth2)を発見する
            var touchingEdges = await FetchEdgesTouchingAsync(conn, depth1Ids, ct);

            var depth2Ids = touchingEdges
                .SelectMany(e => new[] { e.FromPersonId, e.ToPersonId })
                .Where(id => !depth1Ids.Contains(id))
                .Distinct()
                .Take(depth2Limit)
                .ToList();

            // 二次接点（depth2）も、自分が登録した人物（OwnerUserId）のみを対象とする。チーム共有・閲覧権限管理
            // （F-019）は未実装のため、他ユーザーが登録した人物が自分の人脈経由で見えてしまうのを防ぐ
            // （ダッシュボード・人物一覧と同じ方針。深さ1の直接の人脈だけでなく2でも一貫させる）。
            var depth2Rows = depth2Ids.Count == 0
                ? []
                : await _db.PersonsRead
                    .Where(r => depth2Ids.Contains(r.PersonId) && r.OrgId == orgId && r.OwnerUserId == ownerUserId && !r.IsSelf)
                    .Select(r => new { r.PersonId, r.FullName, r.CompanyName, r.IndustryName, r.OccupationName })
                    .ToListAsync(ct);

            var allIds = depth1Ids.Concat(depth2Rows.Select(r => r.PersonId)).ToHashSet();

            var nodes = new List<NetworkNode> { selfNode };
            nodes.AddRange(depth1.Select(p => new NetworkNode(p.PersonId, p.FullName, p.CompanyName, p.IndustryName, p.OccupationName, 1)));
            nodes.AddRange(depth2Rows.Select(p => new NetworkNode(p.PersonId, p.FullName, p.CompanyName, p.IndustryName, p.OccupationName, 2)));

            var edges = new List<NetworkEdge>();
            // 「自分」→直接の人脈 は実データではなく、中心ノードを表現するための合成エッジ（強さは固定値）
            edges.AddRange(depth1.Select(p =>
                new NetworkEdge(Guid.NewGuid(), SelfPersonId, p.PersonId, "self", 3)));
            // 人脈同士の実際の関係（depth1-depth1 / depth1-depth2）
            edges.AddRange(touchingEdges.Where(e => allIds.Contains(e.FromPersonId) && allIds.Contains(e.ToPersonId)));

            return new NetworkGraph(nodes, edges);
        }
        finally
        {
            if (shouldClose)
            {
                await conn.CloseAsync();
            }
        }
    }

    // 特定の人物を起点とした距離maxDepthまでのグラフ（人物カルテからの「この人の周辺を見る」用途）
    public async Task<NetworkGraph> GetNetworkAsync(Guid rootPersonId, Guid orgId, int maxDepth = 2, CancellationToken ct = default)
    {
        maxDepth = Math.Clamp(maxDepth, 0, 3); // リスクR-007対応: 深さの上限を3までに制限する

        var conn = (NpgsqlConnection)_db.Database.GetDbConnection();
        var shouldClose = conn.State != System.Data.ConnectionState.Open;
        if (shouldClose)
        {
            await conn.OpenAsync(ct);
        }

        try
        {
            var depthByPersonId = await CollectReachablePersonIdsAsync(conn, rootPersonId, maxDepth, ct);
            if (depthByPersonId.Count == 0)
            {
                return new NetworkGraph(Array.Empty<NetworkNode>(), Array.Empty<NetworkEdge>());
            }

            var ids = depthByPersonId.Keys.ToList();
            var rows = await _db.PersonsRead
                .Where(r => ids.Contains(r.PersonId) && r.OrgId == orgId)
                .Select(r => new { r.PersonId, r.FullName, r.CompanyName, r.IndustryName, r.OccupationName })
                .ToListAsync(ct);

            var nodes = rows
                .Select(r => new NetworkNode(r.PersonId, r.FullName, r.CompanyName, r.IndustryName, r.OccupationName, depthByPersonId[r.PersonId]))
                .ToList();

            var nodeIdSet = nodes.Select(n => n.PersonId).ToHashSet();
            var edges = await FetchEdgesAsync(conn, nodeIdSet, ct);

            return new NetworkGraph(nodes, edges);
        }
        finally
        {
            if (shouldClose)
            {
                await conn.CloseAsync();
            }
        }
    }

    // F-027: 他ユーザーの人脈図を業種階層までに限定して閲覧する。個々の人物・職種・会社名は一切取得しない
    // （SELECT自体に含めないことで、フロント実装ミスによる情報漏えいを構造的に防ぐ。基本設計書7.6節参照）。
    public async Task<IReadOnlyList<(string IndustryName, int Count)>> GetIndustryBreakdownAsync(
        Guid targetUserId, Guid orgId, CancellationToken ct = default)
    {
        var rows = await _db.PersonsRead
            .Where(r => r.OwnerUserId == targetUserId && r.OrgId == orgId && !r.IsSelf)
            .GroupBy(r => r.IndustryName)
            .Select(g => new { IndustryName = g.Key, Count = g.Count() })
            .ToListAsync(ct);

        return rows
            .Select(r => (r.IndustryName ?? "業種未設定", r.Count))
            .OrderByDescending(r => r.Count)
            .ToList();
    }

    private static async Task<Dictionary<Guid, int>> CollectReachablePersonIdsAsync(
        NpgsqlConnection conn, Guid rootPersonId, int maxDepth, CancellationToken ct)
    {
        const string sql = """
            WITH RECURSIVE reach(person_id, depth) AS (
                SELECT @root_id::uuid, 0
                UNION
                SELECT
                    CASE WHEN pr.from_person_id = r.person_id THEN pr.to_person_id ELSE pr.from_person_id END,
                    r.depth + 1
                FROM person_relations pr
                JOIN reach r ON pr.from_person_id = r.person_id OR pr.to_person_id = r.person_id
                WHERE r.depth < @max_depth
            )
            SELECT person_id, MIN(depth) AS depth
            FROM reach
            GROUP BY person_id;
            """;

        await using var cmd = new NpgsqlCommand(sql, conn);
        cmd.Parameters.AddWithValue("root_id", rootPersonId);
        cmd.Parameters.AddWithValue("max_depth", maxDepth);

        var result = new Dictionary<Guid, int>();
        await using var reader = await cmd.ExecuteReaderAsync(ct);
        while (await reader.ReadAsync(ct))
        {
            result[reader.GetGuid(0)] = reader.GetInt32(1);
        }
        return result;
    }

    private static async Task<List<NetworkEdge>> FetchEdgesAsync(NpgsqlConnection conn, HashSet<Guid> nodeIds, CancellationToken ct)
    {
        const string sql = """
            SELECT relation_id, from_person_id, to_person_id, relation_type, strength
            FROM person_relations
            WHERE from_person_id = ANY(@ids) AND to_person_id = ANY(@ids);
            """;

        await using var cmd = new NpgsqlCommand(sql, conn);
        cmd.Parameters.AddWithValue("ids", nodeIds.ToArray());
        return await ReadEdgesAsync(cmd, ct);
    }

    // depth1の人脈に「片方でも」関わる関係を取得する（二次接点の発見用。両端がdepth1である必要はない）
    private static async Task<List<NetworkEdge>> FetchEdgesTouchingAsync(NpgsqlConnection conn, HashSet<Guid> nodeIds, CancellationToken ct)
    {
        const string sql = """
            SELECT relation_id, from_person_id, to_person_id, relation_type, strength
            FROM person_relations
            WHERE from_person_id = ANY(@ids) OR to_person_id = ANY(@ids);
            """;

        await using var cmd = new NpgsqlCommand(sql, conn);
        cmd.Parameters.AddWithValue("ids", nodeIds.ToArray());
        return await ReadEdgesAsync(cmd, ct);
    }

    private static async Task<List<NetworkEdge>> ReadEdgesAsync(NpgsqlCommand cmd, CancellationToken ct)
    {
        var result = new List<NetworkEdge>();
        await using var reader = await cmd.ExecuteReaderAsync(ct);
        while (await reader.ReadAsync(ct))
        {
            result.Add(new NetworkEdge(
                reader.GetGuid(0), reader.GetGuid(1), reader.GetGuid(2),
                reader.GetString(3), reader.GetInt16(4)));
        }
        return result;
    }
}
