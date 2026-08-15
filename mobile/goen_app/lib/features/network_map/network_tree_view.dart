import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../persons/models/person_models.dart';

/// F-006: 業種＞職種＞会社名＞人物の階層グループ（末端は人物ではなくグループの場合に使う）。
/// 業種・職種・会社名のいずれかが未設定の人物は、それぞれ「未設定」の1グループに集約する。
class TreeGroupNode {
  TreeGroupNode({required this.key, required this.label, required this.children});

  final String key;
  final String label;
  /// 要素は [TreeGroupNode]（さらに下位階層）または [NetworkNode]（人物、末端）のいずれか
  final List<Object> children;

  int get personCount {
    var count = 0;
    for (final child in children) {
      count += child is TreeGroupNode ? child.personCount : 1;
    }
    return count;
  }
}

const _unsetIndustryLabel = '業種未設定';
const _unsetOccupationLabel = '職種未設定';
const _unsetCompanyLabel = '会社名未設定';

/// 自分以外の人物ノードを業種＞職種＞会社名の順にグルーピングしてツリーを構築する。
List<TreeGroupNode> buildIndustryTree(NetworkGraph graph) {
  final persons = graph.nodes.where((n) => !n.isSelf).toList();
  return _groupBy(persons, (p) => _labelOrUnset(p.industryName, _unsetIndustryLabel), '')
      .map((entry) => TreeGroupNode(
            key: entry.key,
            label: entry.key,
            children: _groupBy(entry.value, (p) => _labelOrUnset(p.occupationName, _unsetOccupationLabel), entry.key)
                .map((occEntry) => TreeGroupNode(
                      key: '${entry.key}|${occEntry.key}',
                      label: occEntry.key,
                      children: _groupBy(
                              occEntry.value, (p) => _labelOrUnset(p.companyName, _unsetCompanyLabel), occEntry.key)
                          .map((companyEntry) => TreeGroupNode(
                                key: '${entry.key}|${occEntry.key}|${companyEntry.key}',
                                label: companyEntry.key,
                                children: List<NetworkNode>.of(companyEntry.value)
                                  ..sort((a, b) => a.fullName.compareTo(b.fullName)),
                              ))
                          .toList(),
                    ))
                .toList(),
          ))
      .toList();
}

String _labelOrUnset(String? value, String fallback) => (value == null || value.isEmpty) ? fallback : value;

List<MapEntry<String, List<NetworkNode>>> _groupBy(
  List<NetworkNode> items,
  String Function(NetworkNode) keyOf,
  String parentKey,
) {
  final map = <String, List<NetworkNode>>{};
  for (final item in items) {
    map.putIfAbsent(keyOf(item), () => []).add(item);
  }
  final entries = map.entries.toList()
    ..sort((a, b) {
      const unsetLabels = {_unsetIndustryLabel, _unsetOccupationLabel, _unsetCompanyLabel};
      if (unsetLabels.contains(a.key) && !unsetLabels.contains(b.key)) return 1;
      if (!unsetLabels.contains(a.key) && unsetLabels.contains(b.key)) return -1;
      return a.key.compareTo(b.key);
    });
  return entries;
}

// ブランチ（業種）ごとに割り当てる基準色。同じ色相の濃淡を階層が深くなるほど明るくして使う。
const _branchPalette = [
  Color(0xFFE04B4B), // red
  Color(0xFF3B7DDB), // blue
  Color(0xFFE0A72E), // amber
  Color(0xFF3EA35D), // green
  Color(0xFF8C4FDB), // purple
  Color(0xFF2CADA8), // teal
  Color(0xFFDB6B2C), // orange
  Color(0xFFC24F8E), // pink
];

Color _shadeForDepth(Color base, int depth) {
  final hsl = HSLColor.fromColor(base);
  final lightness = math.min(0.92, hsl.lightness + depth * 0.16);
  return hsl.withLightness(lightness).toColor();
}

class _LayoutNode {
  _LayoutNode({
    required this.key,
    required this.parentKey,
    required this.label,
    required this.position,
    required this.depth,
    required this.color,
    required this.isPerson,
    this.personId,
    this.count,
    this.isCollapsed = false,
    this.isCollapsible = false,
  });

  final String key;
  final String? parentKey;
  final String label;
  Offset position;
  final int depth;
  final Color color;
  final bool isPerson;
  final String? personId;
  final int? count;
  final bool isCollapsed;
  final bool isCollapsible;
}

class _LayoutEdge {
  _LayoutEdge({required this.from, required this.to, required this.color});

  final Offset from;
  final Offset to;
  final Color color;
}

const double _levelWidthStep = 200;
const double _rowHeight = 56;

/// 業種＞職種＞会社名＞人物のツリーを、自分を中心に左右にのみ広がる固定レイアウトに変換する。
/// 業種グループは左右どちらかの列に振り分けられ、同じ列に属する項目は増えるほど縦に積み上がる
/// （四方八方に伸びる放射状レイアウトはやめ、左右2方向・列固定にすることで見やすさを優先する）。
/// 各ブランチ（業種）に固有の色相を割り当て、階層が深くなるほど淡い色調にする。
class _HorizontalLayout {
  _HorizontalLayout({required List<TreeGroupNode> groups, required Set<String> collapsed}) {
    if (groups.isEmpty) return;

    // 色は列に振り分ける前の元の並び順で固定し、左右どちらに行っても同じ業種は同じ色になるようにする。
    final colorOf = <TreeGroupNode, Color>{
      for (var i = 0; i < groups.length; i++) groups[i]: _branchPalette[i % _branchPalette.length],
    };

    // 人数が多い業種から順に、その時点で人数の少ない側へ割り振ることで左右のバランスを取る。
    final sortedByWeight = [...groups]..sort((a, b) => _weightOf(b, collapsed).compareTo(_weightOf(a, collapsed)));
    final rightGroups = <TreeGroupNode>[];
    final leftGroups = <TreeGroupNode>[];
    var rightWeight = 0.0;
    var leftWeight = 0.0;
    for (final group in sortedByWeight) {
      final weight = _weightOf(group, collapsed);
      if (rightWeight <= leftWeight) {
        rightGroups.add(group);
        rightWeight += weight;
      } else {
        leftGroups.add(group);
        leftWeight += weight;
      }
    }

    final rightStart = nodes.length;
    _cursor = 0;
    for (final group in rightGroups) {
      _layoutNode(group, depth: 1, isLeft: false, branchColor: colorOf[group]!, collapsed: collapsed, parentKey: null);
    }
    _shiftY(rightStart, nodes.length, -_cursor / 2);

    final leftStart = nodes.length;
    _cursor = 0;
    for (final group in leftGroups) {
      _layoutNode(group, depth: 1, isLeft: true, branchColor: colorOf[group]!, collapsed: collapsed, parentKey: null);
    }
    _shiftY(leftStart, nodes.length, -_cursor / 2);

    final positionByKey = {for (final n in nodes) n.key: n.position};
    for (final n in nodes) {
      final from = n.parentKey == null ? Offset.zero : (positionByKey[n.parentKey] ?? Offset.zero);
      edges.add(_LayoutEdge(from: from, to: n.position, color: n.color));
    }

    final maxX = nodes.isEmpty ? 0.0 : nodes.map((n) => n.position.dx.abs()).reduce(math.max);
    final maxY = nodes.isEmpty ? 0.0 : nodes.map((n) => n.position.dy.abs()).reduce(math.max);
    width = (maxX + 260) * 2;
    height = (maxY + 160) * 2;
  }

  final List<_LayoutNode> nodes = [];
  final List<_LayoutEdge> edges = [];
  double width = 700;
  double height = 700;
  double _cursor = 0;

  double _weightOf(Object node, Set<String> collapsed) {
    if (node is NetworkNode) return 1;
    final group = node as TreeGroupNode;
    if (collapsed.contains(group.key) || group.children.isEmpty) return 1;
    return group.children.fold<double>(0, (sum, c) => sum + _weightOf(c, collapsed));
  }

  void _shiftY(int start, int end, double dy) {
    for (var i = start; i < end; i++) {
      nodes[i].position = nodes[i].position.translate(0, dy);
    }
  }

  /// 深さ方向（業種→職種→会社名→人物）は中心から外へ、同じ深さの兄弟は縦に積み上げて配置する
  /// 標準的な横型ツリーレイアウト。戻り値はこのノードのy座標（親の位置決めに使う）。
  double _layoutNode(
    Object node, {
    required int depth,
    required bool isLeft,
    required Color branchColor,
    required Set<String> collapsed,
    required String? parentKey,
  }) {
    final x = (isLeft ? -1.0 : 1.0) * depth * _levelWidthStep;
    final color = _shadeForDepth(branchColor, depth - 1);

    if (node is NetworkNode) {
      final y = _cursor;
      _cursor += _rowHeight;
      final key = 'p:${node.personId}';
      nodes.add(_LayoutNode(
        key: key,
        parentKey: parentKey,
        label: node.fullName,
        position: Offset(x, y),
        depth: depth,
        color: color,
        isPerson: true,
        personId: node.personId,
      ));
      return y;
    }

    final group = node as TreeGroupNode;
    final isCollapsed = collapsed.contains(group.key);
    double y;
    if (isCollapsed || group.children.isEmpty) {
      y = _cursor;
      _cursor += _rowHeight;
    } else {
      final childYs = [
        for (final child in group.children)
          _layoutNode(child, depth: depth + 1, isLeft: isLeft, branchColor: branchColor, collapsed: collapsed, parentKey: group.key),
      ];
      y = childYs.reduce((a, b) => a + b) / childYs.length;
    }

    nodes.add(_LayoutNode(
      key: group.key,
      parentKey: parentKey,
      label: group.label,
      position: Offset(x, y),
      depth: depth,
      color: color,
      isPerson: false,
      count: group.personCount,
      isCollapsed: isCollapsed,
      isCollapsible: group.children.isNotEmpty,
    ));
    return y;
  }
}

/// 自分を中心に、左右2方向にのみ業種＞職種＞会社名＞人物の階層を展開するマインドマップ表示。
/// 業種は人数バランスを見て左右の列に振り分けられ、同じ列内で項目が増えると縦に積み上がる
/// （全方位に伸びる見た目は使いづらいとのフィードバックを受け、左右固定のレイアウトにしている）。
/// 各階層は折りたたみ可能で、折りたたむと配下の人数を表示する。
/// 紹介者・人脈知人の関係は線としては描画しない（線が輻輳して見づらいため）。関係の詳細は人物カルテで確認する。
class NetworkTreeView extends StatefulWidget {
  const NetworkTreeView({
    super.key,
    required this.graph,
    required this.onPersonTap,
    this.selfLabel = '自分',
  });

  final NetworkGraph graph;
  final void Function(String personId) onPersonTap;
  final String selfLabel;

  @override
  State<NetworkTreeView> createState() => _NetworkTreeViewState();
}

class _NetworkTreeViewState extends State<NetworkTreeView> {
  late final Set<String> _collapsed = _allGroupKeys(buildIndustryTree(widget.graph));
  final TransformationController _transformController = TransformationController();
  bool _initialCentered = false;

  static Set<String> _allGroupKeys(List<TreeGroupNode> groups) {
    final keys = <String>{};
    void visit(TreeGroupNode group) {
      keys.add(group.key);
      for (final child in group.children) {
        if (child is TreeGroupNode) visit(child);
      }
    }

    for (final group in groups) {
      visit(group);
    }
    return keys;
  }

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final groups = buildIndustryTree(widget.graph);

    if (groups.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('まだ人物が登録されていません。', textAlign: TextAlign.center),
        ),
      );
    }

    final layout = _HorizontalLayout(groups: groups, collapsed: _collapsed);
    final center = Offset(layout.width / 2, layout.height / 2);

    return LayoutBuilder(
      builder: (context, constraints) {
        if (!_initialCentered && constraints.maxWidth.isFinite && constraints.maxHeight.isFinite) {
          _initialCentered = true;
          final viewportSize = Size(constraints.maxWidth, constraints.maxHeight);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _transformController.value = Matrix4.identity()
              ..translateByDouble(viewportSize.width / 2 - center.dx, viewportSize.height / 2 - center.dy, 0, 1);
          });
        }

        return InteractiveViewer(
          transformationController: _transformController,
          minScale: 0.25,
          maxScale: 3,
          boundaryMargin: const EdgeInsets.all(200),
          constrained: false,
          child: SizedBox(
            width: layout.width,
            height: layout.height,
            child: Stack(
              children: [
                CustomPaint(
                  size: Size(layout.width, layout.height),
                  painter: _EdgePainter(structuralEdges: layout.edges, center: center),
                ),
                _buildSelfNode(center),
                for (final node in layout.nodes) _buildNode(node, center),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSelfNode(Offset center) {
    final scheme = Theme.of(context).colorScheme;
    return Positioned(
      left: center.dx,
      top: center.dy,
      child: FractionalTranslation(
        translation: const Offset(-0.5, -0.5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(radius: 30, backgroundColor: scheme.primary, child: Icon(Icons.person, color: scheme.onPrimary, size: 30)),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: scheme.surface, borderRadius: BorderRadius.circular(8), boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 4),
              ]),
              child: Text(widget.selfLabel, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNode(_LayoutNode node, Offset center) {
    final position = center + node.position;
    final textColor = node.depth >= 3 ? Colors.black87 : Colors.white;

    return Positioned(
      left: position.dx,
      top: position.dy,
      child: FractionalTranslation(
        translation: const Offset(-0.5, -0.5),
        child: GestureDetector(
          onTap: () {
            if (node.isPerson) {
              widget.onPersonTap(node.personId!);
            } else if (node.isCollapsible) {
              setState(() {
                if (node.isCollapsed) {
                  _collapsed.remove(node.key);
                } else {
                  _collapsed.add(node.key);
                }
              });
            }
          },
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 160),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: node.color,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 4, offset: const Offset(0, 2))],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!node.isPerson)
                    Icon(node.isCollapsed ? Icons.chevron_right : Icons.expand_more, size: 14, color: textColor),
                  if (node.isPerson) Icon(Icons.person_outline, size: 13, color: textColor),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      node.label,
                      style: TextStyle(color: textColor, fontSize: node.isPerson ? 12 : 12.5, fontWeight: node.isPerson ? FontWeight.normal : FontWeight.w600),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (node.count != null) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(8)),
                      child: Text('${node.count}', style: TextStyle(color: textColor, fontSize: 10)),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EdgePainter extends CustomPainter {
  _EdgePainter({required this.structuralEdges, required this.center});

  final List<_LayoutEdge> structuralEdges;
  final Offset center;

  @override
  void paint(Canvas canvas, Size size) {
    for (final edge in structuralEdges) {
      _drawCurve(canvas, center + edge.from, center + edge.to, edge.color);
    }
  }

  void _drawCurve(Canvas canvas, Offset from, Offset to, Color color) {
    final path = Path()..moveTo(from.dx, from.dy);
    // 両端で水平な接線になるように制御点を置き、横方向のツリーらしい滑らかな曲線にする
    final midX = (from.dx + to.dx) / 2;
    path.cubicTo(midX, from.dy, midX, to.dy, to.dx, to.dy);

    final paint = Paint()
      ..color = color.withValues(alpha: 0.55)
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _EdgePainter oldDelegate) => oldDelegate.structuralEdges != structuralEdges;
}
