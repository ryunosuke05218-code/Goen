import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../persons/models/person_models.dart';
import '../persons/relation_type.dart';

/// グラフに含まれる関係種別の一覧（"self"の合成エッジは表示切替の対象外のため除く）
Set<String> relationTypesIn(NetworkGraph graph) =>
    graph.edges.map((e) => e.relationType).where((t) => t != 'self').toSet();

/// どの関係種別・深さのつながりを表示するかのフィルタ設定。
/// depth0（自分）・depth1（直接の人脈）は常に表示し、depth2（二次接点）と関係種別のみ絞り込む。
class NetworkGraphFilter {
  const NetworkGraphFilter({required this.visibleTypes, this.showSecondDegree = true});

  final Set<String> visibleTypes;
  final bool showSecondDegree;

  factory NetworkGraphFilter.all(NetworkGraph graph) =>
      NetworkGraphFilter(visibleTypes: relationTypesIn(graph));

  NetworkGraphFilter copyWith({Set<String>? visibleTypes, bool? showSecondDegree}) => NetworkGraphFilter(
        visibleTypes: visibleTypes ?? this.visibleTypes,
        showSecondDegree: showSecondDegree ?? this.showSecondDegree,
      );

  NetworkGraph apply(NetworkGraph graph) {
    final depth2Ids = graph.nodes.where((n) => n.depth >= 2).map((n) => n.personId).toSet();
    final alwaysVisibleIds = graph.nodes.where((n) => n.depth <= 1).map((n) => n.personId).toSet();

    final filteredEdges = graph.edges.where((e) {
      if (e.relationType != 'self' && !visibleTypes.contains(e.relationType)) return false;
      if (!showSecondDegree && (depth2Ids.contains(e.fromPersonId) || depth2Ids.contains(e.toPersonId))) {
        return false;
      }
      return true;
    }).toList();

    final visibleIds = {...alwaysVisibleIds};
    if (showSecondDegree) {
      for (final e in filteredEdges) {
        visibleIds.add(e.fromPersonId);
        visibleIds.add(e.toPersonId);
      }
    }

    return NetworkGraph(
      nodes: graph.nodes.where((n) => visibleIds.contains(n.personId)).toList(),
      edges: filteredEdges.where((e) => visibleIds.contains(e.fromPersonId) && visibleIds.contains(e.toPersonId)).toList(),
    );
  }
}

/// 表示フィルタ（関係種別・二次接点の有無）を選ぶボトムシート
Future<NetworkGraphFilter?> showNetworkFilterSheet(
  BuildContext context, {
  required NetworkGraphFilter current,
  required Set<String> availableTypes,
}) {
  return showModalBottomSheet<NetworkGraphFilter>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _NetworkFilterSheet(initial: current, availableTypes: availableTypes),
  );
}

class _NetworkFilterSheet extends StatefulWidget {
  const _NetworkFilterSheet({required this.initial, required this.availableTypes});

  final NetworkGraphFilter initial;
  final Set<String> availableTypes;

  @override
  State<_NetworkFilterSheet> createState() => _NetworkFilterSheetState();
}

class _NetworkFilterSheetState extends State<_NetworkFilterSheet> {
  late Set<String> _visibleTypes = {...widget.initial.visibleTypes};
  late bool _showSecondDegree = widget.initial.showSecondDegree;

  @override
  Widget build(BuildContext context) {
    final sortedTypes = widget.availableTypes.toList()..sort();

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('表示するつながり', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          const Text('チェックを外すと、その種類の線とノードを非表示にできます', style: TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 12),
          if (sortedTypes.isEmpty)
            const Text('まだ人脈同士のつながりが登録されていません')
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final type in sortedTypes)
                  FilterChip(
                    label: Text(RelationTypeStyle.label(type)),
                    avatar: CircleAvatar(backgroundColor: RelationTypeStyle.color(type), radius: 6),
                    selected: _visibleTypes.contains(type),
                    onSelected: (selected) => setState(() {
                      if (selected) {
                        _visibleTypes.add(type);
                      } else {
                        _visibleTypes.remove(type);
                      }
                    }),
                  ),
              ],
            ),
          const Divider(height: 32),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('二次的なつながりも表示'),
            subtitle: const Text('OFFにすると、直接の人脈のみのシンプルな表示になります'),
            value: _showSecondDegree,
            onChanged: (v) => setState(() => _showSecondDegree = v),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => setState(() {
                    _visibleTypes = {...widget.availableTypes};
                    _showSecondDegree = true;
                  }),
                  child: const Text('すべて表示'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(
                    NetworkGraphFilter(visibleTypes: _visibleTypes, showSecondDegree: _showSecondDegree),
                  ),
                  child: const Text('この条件で表示'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 人脈グラフをマインドマップ風（中心ノード＋同心円状の関連ノード）に描画する共有ウィジェット。
/// - `/network-map`（自分を中心とした全体マップ）
/// - `/persons/:id/network`（特定人物を起点とした周辺マップ）
/// の両方から利用する。
class GraphView extends StatelessWidget {
  const GraphView({super.key, required this.graph, required this.onNodeTap, this.centerPersonId});

  final NetworkGraph graph;
  final void Function(String personId) onNodeTap;
  final String? centerPersonId;

  @override
  Widget build(BuildContext context) {
    final layout = _GraphLayout(graph);

    return Column(
      children: [
        Expanded(
          child: InteractiveViewer(
            minScale: 0.4,
            maxScale: 3,
            boundaryMargin: const EdgeInsets.all(120),
            child: SizedBox(
              width: layout.canvasSize,
              height: layout.canvasSize,
              child: Stack(
                children: [
                  CustomPaint(
                    size: Size(layout.canvasSize, layout.canvasSize),
                    painter: _EdgePainter(edges: graph.edges, positions: layout.positions),
                  ),
                  for (final node in graph.nodes)
                    if (layout.positions[node.personId] case final pos?)
                      _NodeMarker(
                        node: node,
                        position: pos,
                        isCenter: node.personId == centerPersonId,
                        onTap: () {
                          // 合成の「自分」ノード（isSelf）だけはカルテが存在しないためタップ無効。
                          // 特定人物起点のグラフでは中心ノードも実在の人物なのでタップ可能にする。
                          if (!node.isSelf) onNodeTap(node.personId);
                        },
                      ),
                ],
              ),
            ),
          ),
        ),
        _Legend(edges: graph.edges),
      ],
    );
  }
}

class _GraphLayout {
  _GraphLayout(NetworkGraph graph) {
    final byDepth = <int, List<NetworkNode>>{};
    for (final node in graph.nodes) {
      byDepth.putIfAbsent(node.depth, () => []).add(node);
    }

    final maxDepth = byDepth.keys.isEmpty ? 0 : byDepth.keys.reduce(math.max);
    var maxRadius = 0.0;

    byDepth.forEach((depth, nodes) {
      final radius = _radiusFor(depth, nodes.length);
      maxRadius = math.max(maxRadius, radius);
      if (radius == 0) {
        positions[nodes.first.personId] = Offset.zero;
        return;
      }
      for (var i = 0; i < nodes.length; i++) {
        // 12時方向から時計回りに配置する（マインドマップらしい見た目にするため）
        final angle = -math.pi / 2 + (2 * math.pi * i) / nodes.length;
        positions[nodes[i].personId] = Offset(radius * math.cos(angle), radius * math.sin(angle));
      }
    });

    canvasSize = (maxRadius + _nodeMaxHalfSize + 60) * 2;
    if (maxDepth == 0) canvasSize = 320; // ノードが自分のみの場合の最小サイズ

    // 原点(0,0)を中心とみなしていたため、キャンバス座標系（左上原点）へシフトする
    final center = Offset(canvasSize / 2, canvasSize / 2);
    positions.updateAll((key, value) => value + center);
  }

  final Map<String, Offset> positions = {};
  double canvasSize = 320;

  static const _nodeMaxHalfSize = 60.0;

  static double _radiusFor(int depth, int countAtDepth) {
    if (depth <= 0) return 0;
    final base = depth == 1 ? 130.0 : 250.0;
    const perNodeArc = 62.0; // 円周上で確保したい最低間隔(px)
    final radiusForSpacing = (perNodeArc * countAtDepth) / (2 * math.pi);
    return math.max(base, radiusForSpacing);
  }
}

class _NodeMarker extends StatelessWidget {
  const _NodeMarker({required this.node, required this.position, required this.isCenter, required this.onTap});

  final NetworkNode node;
  final Offset position;
  final bool isCenter;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final diameter = node.isSelf ? 76.0 : (node.depth == 1 ? 44.0 + node.importance * 4 : 30.0 + node.importance * 3);

    final Color bgColor;
    final Color fgColor;
    if (node.isSelf) {
      bgColor = scheme.primary;
      fgColor = scheme.onPrimary;
    } else if (node.depth == 1) {
      bgColor = scheme.secondaryContainer;
      fgColor = scheme.onSecondaryContainer;
    } else {
      bgColor = scheme.surfaceContainerHighest;
      fgColor = scheme.onSurfaceVariant;
    }

    return Positioned(
      left: position.dx - 55,
      top: position.dy - diameter / 2,
      width: 110,
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: diameter,
              height: diameter,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: bgColor,
                border: isCenter && !node.isSelf ? Border.all(color: scheme.primary, width: 3) : null,
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 6, offset: const Offset(0, 2)),
                ],
              ),
              alignment: Alignment.center,
              child: node.isSelf
                  ? Icon(Icons.person, color: fgColor, size: 32)
                  : Text('★${node.importance}', style: TextStyle(color: fgColor, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                node.fullName,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: node.isSelf || isCenter ? FontWeight.bold : FontWeight.normal,
                    ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EdgePainter extends CustomPainter {
  _EdgePainter({required this.edges, required this.positions});

  final List<NetworkEdge> edges;
  final Map<String, Offset> positions;

  @override
  void paint(Canvas canvas, Size size) {
    // 自分からの合成エッジ(self)を先に描き、実際の人脈関係を後から重ねて見やすくする
    final sorted = [...edges]..sort((a, b) => (a.relationType == 'self' ? 0 : 1) - (b.relationType == 'self' ? 0 : 1));

    for (final edge in sorted) {
      final from = positions[edge.fromPersonId];
      final to = positions[edge.toPersonId];
      if (from == null || to == null) continue;

      final isSelfEdge = edge.relationType == 'self';
      final paint = Paint()
        ..color = RelationTypeStyle.color(edge.relationType).withValues(alpha: isSelfEdge ? 0.45 : 0.85)
        ..strokeWidth = isSelfEdge ? 1.6 : (1.2 + edge.strength * 0.9)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(from, to, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _EdgePainter oldDelegate) =>
      oldDelegate.edges != edges || oldDelegate.positions != positions;
}

class _Legend extends StatelessWidget {
  const _Legend({required this.edges});

  final List<NetworkEdge> edges;

  @override
  Widget build(BuildContext context) {
    final types = edges.map((e) => e.relationType).where((t) => t != 'self').toSet().toList()..sort();

    if (types.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Text(
          'まだ人脈同士のつながりが登録されていません。人物カルテの「AIに関係性を提案してもらう」から追加できます。',
          style: TextStyle(fontSize: 12, color: Colors.grey),
          textAlign: TextAlign.center,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 12,
        runSpacing: 4,
        children: [
          for (final type in types)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 10, height: 10, decoration: BoxDecoration(color: RelationTypeStyle.color(type), shape: BoxShape.circle)),
                const SizedBox(width: 4),
                Text(RelationTypeStyle.label(type), style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
        ],
      ),
    );
  }
}
