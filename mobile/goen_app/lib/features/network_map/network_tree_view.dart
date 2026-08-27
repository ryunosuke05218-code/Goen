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
    // 振り分けの基準には折りたたみ状態に依存しないpersonCount（実際の総人数）を使う。
    // ここで_weightOf（折りたたみ状態により1〜personCountの間で変動する値）を使うと、
    // 他のグループを開閉しただけで無関係なグループの左右が入れ替わってしまう不具合があった。
    final sortedByCount = [...groups]..sort((a, b) => b.personCount.compareTo(a.personCount));
    final rightGroups = <TreeGroupNode>[];
    final leftGroups = <TreeGroupNode>[];
    var rightCount = 0;
    var leftCount = 0;
    for (final group in sortedByCount) {
      if (rightCount <= leftCount) {
        rightGroups.add(group);
        rightCount += group.personCount;
      } else {
        leftGroups.add(group);
        leftCount += group.personCount;
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

// ---------------------------------------------------------------------------
// 円形表示（自分を中心に業種を円状配置し、業種同士を輪でつなぐレイアウト）は実装済みだが、
// 別フェーズで対応する方針のためUI（切替ボタン）からは未接続の状態で保留にしている。
// 実機確認済み: 折りたたみ状態からの展開（花のように外側へ広がる見た目）・重なり回避ロジックともに動作。
// 再開する場合は NetworkTreeView に radial: true を渡す呼び出し元（切替ボタン等）を
// network_map_screen.dart に追加するだけでよい（本ファイル側の変更は不要な想定）。
// ---------------------------------------------------------------------------

// 隣接ノード同士が重ならないよう確保する最小円弧長(px)。チップ1個分の見た目の幅を目安にする。
const double _radialMinArcPerLeaf = 100;
// 業種のみ・全折りたたみの最小構成でも十分な間隔になる基準半径。
const double _radialBaseRadiusStep = 220;
// 業種同士をつなぐ「輪」のライン色。特定の業種色に寄せず中立色にする。
const Color _radialRingColor = Color(0xFFB0B8C1);

/// F-006拡張: 自分を中心に業種を円状に配置する表示。業種＞職種＞会社名＞人物の階層は、
/// 業種の位置から放射状（花が開くイメージ）に外側へ展開する。自分↔業種の線は描画せず、
/// 代わりに業種同士を少し太めの線でつなぎ、ひとつの輪として見えるようにする。
///
/// 重なり防止の考え方: 折りたたみ状態での合計ウェイト（_HorizontalLayoutと同じ「葉1個=1」の重み）から
/// 1ウェイトあたりの角度(anglePerUnit)を求め、その角度でも隣接ノードの円弧長が_radialMinArcPerLeaf
/// を下回らないよう半径(_radiusStep)を逆算して広げる。展開が進み合計ウェイトが増えるほど半径全体が
/// 外側に広がるため、どれだけ展開しても隣接ノードの間隔は一定以上に保たれる。
class _RadialLayout {
  _RadialLayout({required List<TreeGroupNode> groups, required Set<String> collapsed}) {
    if (groups.isEmpty) return;

    final colorOf = <TreeGroupNode, Color>{
      for (var i = 0; i < groups.length; i++) groups[i]: _branchPalette[i % _branchPalette.length],
    };

    final totalWeight = groups.fold<double>(0, (sum, g) => sum + _weightOf(g, collapsed));
    final anglePerUnit = totalWeight <= 0 ? 2 * math.pi : (2 * math.pi) / totalWeight;
    _radiusStep = math.max(_radialBaseRadiusStep, _radialMinArcPerLeaf / anglePerUnit);

    _cursor = -math.pi / 2; // 12時の位置を起点に時計回りへ配置する
    for (final group in groups) {
      _layoutNode(group, depth: 1, branchColor: colorOf[group]!, collapsed: collapsed, parentKey: null, anglePerUnit: anglePerUnit);
    }

    final positionByKey = {for (final n in nodes) n.key: n.position};
    for (final n in nodes) {
      if (n.parentKey == null) continue; // 自分↔業種は線でつながない
      final from = positionByKey[n.parentKey] ?? Offset.zero;
      edges.add(_LayoutEdge(from: from, to: n.position, color: n.color));
    }

    final ring = nodes.where((n) => n.depth == 1).toList();
    for (var i = 0; i < ring.length; i++) {
      ringEdges.add(_LayoutEdge(from: ring[i].position, to: ring[(i + 1) % ring.length].position, color: _radialRingColor));
    }

    final maxRadius = nodes.isEmpty ? 0.0 : nodes.map((n) => n.position.distance).reduce(math.max);
    width = (maxRadius + 260) * 2;
    height = (maxRadius + 260) * 2;
  }

  final List<_LayoutNode> nodes = [];
  final List<_LayoutEdge> edges = [];
  final List<_LayoutEdge> ringEdges = [];
  double width = 700;
  double height = 700;
  double _cursor = 0;
  double _radiusStep = _radialBaseRadiusStep;

  double _weightOf(Object node, Set<String> collapsed) {
    if (node is NetworkNode) return 1;
    final group = node as TreeGroupNode;
    if (collapsed.contains(group.key) || group.children.isEmpty) return 1;
    return group.children.fold<double>(0, (sum, c) => sum + _weightOf(c, collapsed));
  }

  /// 深さ方向（業種→職種→会社名→人物）は中心から外へ半径を伸ばし、同じ深さの兄弟は角度方向に
  /// 並べる。戻り値はこのノードの角度（親ノードの位置決めに使う）。
  double _layoutNode(
    Object node, {
    required int depth,
    required Color branchColor,
    required Set<String> collapsed,
    required String? parentKey,
    required double anglePerUnit,
  }) {
    final radius = depth * _radiusStep;
    final color = _shadeForDepth(branchColor, depth - 1);

    if (node is NetworkNode) {
      final angle = _cursor + anglePerUnit / 2;
      _cursor += anglePerUnit;
      final key = 'p:${node.personId}';
      nodes.add(_LayoutNode(
        key: key,
        parentKey: parentKey,
        label: node.fullName,
        position: Offset.fromDirection(angle, radius),
        depth: depth,
        color: color,
        isPerson: true,
        personId: node.personId,
      ));
      return angle;
    }

    final group = node as TreeGroupNode;
    final isCollapsed = collapsed.contains(group.key);
    double angle;
    if (isCollapsed || group.children.isEmpty) {
      angle = _cursor + anglePerUnit / 2;
      _cursor += anglePerUnit;
    } else {
      final childAngles = [
        for (final child in group.children)
          _layoutNode(child,
              depth: depth + 1, branchColor: branchColor, collapsed: collapsed, parentKey: group.key, anglePerUnit: anglePerUnit),
      ];
      angle = childAngles.reduce((a, b) => a + b) / childAngles.length;
    }

    nodes.add(_LayoutNode(
      key: group.key,
      parentKey: parentKey,
      label: group.label,
      position: Offset.fromDirection(angle, radius),
      depth: depth,
      color: color,
      isPerson: false,
      count: group.personCount,
      isCollapsed: isCollapsed,
      isCollapsible: group.children.isNotEmpty,
    ));
    return angle;
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
    this.radial = false,
  });

  final NetworkGraph graph;
  final void Function(String personId) onPersonTap;
  final String selfLabel;
  // false: 左右2方向のツリー表示（既定）。true: 自分を中心に業種を円状に配置する表示。
  final bool radial;

  @override
  State<NetworkTreeView> createState() => _NetworkTreeViewState();
}

class _NetworkTreeViewState extends State<NetworkTreeView> {
  late final Set<String> _collapsed = _allGroupKeys(buildIndustryTree(widget.graph));
  final TransformationController _transformController = TransformationController();
  bool _initialCentered = false;
  // 直前にタップして開閉したノードのkey。次のbuildでそのノードの新しい位置へパンして中央に表示する
  // （折りたたんだ場合は折りたたんだもの自身、開いた場合は開いたもの自身が対象）。
  String? _pendingCenterKey;

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
  void didUpdateWidget(covariant NetworkTreeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 表示形式（ツリー/円形）を切り替えるとキャンバスの大きさ・原点が変わるため、パン位置を再計算させる。
    if (oldWidget.radial != widget.radial) {
      _initialCentered = false;
    }
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

    // キャンバスサイズ・中心座標は、現在の折りたたみ状態ではなく「全展開した場合」を基準に固定する。
    // 折りたたみ状態ごとのレイアウト実寸から中心を求めると、グループを開閉するたびにキャンバス全体の
    // 大きさが変わって中心座標（＝自分の位置）がずれ、パン位置は据え置きのため図がずるずる横に
    // 流れて見える不具合があった（開いたグループが伸びた側へ図全体が寄っていくように見える）。
    // 全展開基準で固定することで、開閉してもキャンバスの大きさ・原点は変わらず表示が安定する。
    final double canvasWidth;
    final double canvasHeight;
    final List<_LayoutNode> layoutNodes;
    final List<_LayoutEdge> structuralEdges;
    final List<_LayoutEdge> ringEdges;
    final bool curvedEdges;

    if (widget.radial) {
      final envelope = _RadialLayout(groups: groups, collapsed: const {});
      final layout = _RadialLayout(groups: groups, collapsed: _collapsed);
      canvasWidth = envelope.width;
      canvasHeight = envelope.height;
      layoutNodes = layout.nodes;
      structuralEdges = layout.edges;
      ringEdges = layout.ringEdges;
      curvedEdges = false;
    } else {
      final envelope = _HorizontalLayout(groups: groups, collapsed: const {});
      final layout = _HorizontalLayout(groups: groups, collapsed: _collapsed);
      canvasWidth = envelope.width;
      canvasHeight = envelope.height;
      layoutNodes = layout.nodes;
      structuralEdges = layout.edges;
      ringEdges = const [];
      curvedEdges = true;
    }
    final center = Offset(canvasWidth / 2, canvasHeight / 2);

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

        // グループの折りたたみ・展開直後は画面中央をパンし直す。
        // ・折りたたんだ場合: タップしたノード自身の新しい位置を中央にする。
        // ・開いた場合: タップしたノード自身ではなく、その直下で新たに現れた子ノード群
        //   （職種・会社名・人物のいずれでも）のバウンディングボックス中心を中央にする。
        if (_pendingCenterKey != null && constraints.maxWidth.isFinite && constraints.maxHeight.isFinite) {
          final targetKey = _pendingCenterKey!;
          _pendingCenterKey = null;

          Offset? targetCanvasPos;
          if (!_collapsed.contains(targetKey)) {
            final children = layoutNodes.where((n) => n.parentKey == targetKey).toList();
            if (children.isNotEmpty) {
              final minX = children.map((n) => n.position.dx).reduce(math.min);
              final maxX = children.map((n) => n.position.dx).reduce(math.max);
              final minY = children.map((n) => n.position.dy).reduce(math.min);
              final maxY = children.map((n) => n.position.dy).reduce(math.max);
              targetCanvasPos = center + Offset((minX + maxX) / 2, (minY + maxY) / 2);
            }
          }
          if (targetCanvasPos == null) {
            final matches = layoutNodes.where((n) => n.key == targetKey);
            if (matches.isNotEmpty) targetCanvasPos = center + matches.first.position;
          }

          if (targetCanvasPos != null) {
            final pos = targetCanvasPos;
            final viewportSize = Size(constraints.maxWidth, constraints.maxHeight);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              final scale = _transformController.value.getMaxScaleOnAxis();
              _transformController.value = Matrix4.identity()
                ..translateByDouble(
                  viewportSize.width / 2 - pos.dx * scale,
                  viewportSize.height / 2 - pos.dy * scale,
                  0,
                  1,
                )
                ..scaleByDouble(scale, scale, scale, 1);
            });
          }
        }

        return InteractiveViewer(
          transformationController: _transformController,
          minScale: 0.25,
          maxScale: 3,
          boundaryMargin: const EdgeInsets.all(200),
          constrained: false,
          child: SizedBox(
            width: canvasWidth,
            height: canvasHeight,
            child: Stack(
              children: [
                CustomPaint(
                  size: Size(canvasWidth, canvasHeight),
                  painter: _EdgePainter(structuralEdges: structuralEdges, ringEdges: ringEdges, center: center, curved: curvedEdges),
                ),
                _buildSelfNode(center),
                for (final node in layoutNodes) _buildNode(node, center),
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
                _pendingCenterKey = node.key;
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
  _EdgePainter({
    required this.structuralEdges,
    required this.center,
    this.ringEdges = const [],
    this.curved = true,
  });

  final List<_LayoutEdge> structuralEdges;
  final List<_LayoutEdge> ringEdges;
  final Offset center;
  // true: ツリー表示用の水平接線カーブ。false: 円形表示用の直線（中心から放射状に伸びる見た目にする）。
  final bool curved;

  @override
  void paint(Canvas canvas, Size size) {
    // 業種同士をつなぐ「輪」を先に描き、階層の線をその上に重ねる
    for (final edge in ringEdges) {
      _drawStraight(canvas, center + edge.from, center + edge.to, edge.color, strokeWidth: 4.5, alpha: 0.5);
    }
    for (final edge in structuralEdges) {
      if (curved) {
        _drawCurve(canvas, center + edge.from, center + edge.to, edge.color);
      } else {
        _drawStraight(canvas, center + edge.from, center + edge.to, edge.color, strokeWidth: 2.2, alpha: 0.55);
      }
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

  void _drawStraight(Canvas canvas, Offset from, Offset to, Color color, {required double strokeWidth, required double alpha}) {
    final paint = Paint()
      ..color = color.withValues(alpha: alpha)
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(from, to, paint);
  }

  @override
  bool shouldRepaint(covariant _EdgePainter oldDelegate) =>
      oldDelegate.structuralEdges != structuralEdges || oldDelegate.ringEdges != ringEdges || oldDelegate.curved != curved;
}
