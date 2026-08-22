import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'models/assistant_models.dart';

// AI指示の結果（おすすめの経路・関連しそうな人物）を、リスト表示の代わりに図で見せるための軽量な図。
// 人脈マップ（NetworkTreeView）と同じ「自分を中心に左右2方向にのみ広がる・分岐ごとに固定の色」という
// 視覚言語を踏襲する（全方位に伸びる放射状レイアウトは過去のフィードバックで見づらいとされたため避ける）。
// 経路（自分→…→対象人物の紹介チェーン）は実線、関連しそうな人物（AIヒント）は点線で区別する。
class AiResultDiagram extends StatefulWidget {
  const AiResultDiagram({
    super.key,
    required this.routes,
    required this.hints,
    required this.onPersonTap,
    this.selfLabel = '自分',
  });

  final List<AssistantRoute> routes;
  final List<AssistantHint> hints;
  final void Function(String personId) onPersonTap;
  final String selfLabel;

  @override
  State<AiResultDiagram> createState() => _AiResultDiagramState();
}

class _AiResultDiagramState extends State<AiResultDiagram> {
  final TransformationController _transformController = TransformationController();
  bool _initialCentered = false;

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final layout = _DiagramLayout(routes: widget.routes, hints: widget.hints);
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
          minScale: 0.4,
          maxScale: 2.5,
          boundaryMargin: const EdgeInsets.all(120),
          constrained: false,
          child: SizedBox(
            width: layout.width,
            height: layout.height,
            child: Stack(
              children: [
                CustomPaint(
                  size: Size(layout.width, layout.height),
                  painter: _DiagramEdgePainter(edges: layout.edges, center: center),
                ),
                _buildSelfNode(context, center),
                for (final node in layout.nodes) ..._buildNode(context, node, center),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSelfNode(BuildContext context, Offset center) {
    final scheme = Theme.of(context).colorScheme;
    return Positioned(
      left: center.dx,
      top: center.dy,
      child: FractionalTranslation(
        translation: const Offset(-0.5, -0.5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(radius: 24, backgroundColor: scheme.primary, child: Icon(Icons.person, color: scheme.onPrimary, size: 24)),
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

  // チップ（人物ノード本体）とキャプション（提案理由等）を別々のPositionedとして返す。
  // 以前はColumnでキャプション＋チップをまとめて中心寄せしていたため、エッジの接続先（chipの中心）と
  // 実際に画面へ表示されるchipの中心がずれ、線が人物ノードにしっかり繋がって見えない原因になっていた。
  // チップ単体を`position`（エッジの接続先と同じ座標）で中心寄せすることで、線が必ずchipの中心に届くようにする。
  List<Widget> _buildNode(BuildContext context, _LayoutNode node, Offset center) {
    final position = center + node.position;

    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: node.color,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 4, offset: const Offset(0, 2))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(node.isHint ? Icons.lightbulb_outline : Icons.person_outline, size: 13, color: Colors.white),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 120),
            child: Text(
              node.label,
              style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );

    return [
      if (node.caption != null)
        Positioned(
          left: position.dx,
          top: position.dy,
          child: FractionalTranslation(
            // dy=-1.0でキャプション自身の下端がposition.dyに揃うようにし、
            // 内側のmarginでchipの上端（おおよそ半分の高さ分）より上に離す。
            translation: const Offset(-0.5, -1.0),
            child: Container(
              margin: const EdgeInsets.only(bottom: 20),
              child: Tooltip(
                message: node.caption!,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  constraints: const BoxConstraints(maxWidth: 130),
                  decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(6)),
                  child: Text(
                    node.caption!,
                    style: const TextStyle(fontSize: 10, color: Colors.black54),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
          ),
        ),
      Positioned(
        left: position.dx,
        top: position.dy,
        child: FractionalTranslation(
          translation: const Offset(-0.5, -0.5),
          child: GestureDetector(
            onTap: () => widget.onPersonTap(node.personId),
            child: chip,
          ),
        ),
      ),
    ];
  }
}

// ブランチ（経路・ヒントの1件ずつ）ごとに割り当てる基準色。人脈マップと同じパレットを使い、視覚的な一貫性を保つ。
const _palette = [
  Color(0xFFE04B4B),
  Color(0xFF3B7DDB),
  Color(0xFFE0A72E),
  Color(0xFF3EA35D),
  Color(0xFF8C4FDB),
  Color(0xFF2CADA8),
  Color(0xFFDB6B2C),
  Color(0xFFC24F8E),
];

Color _shadeForDepth(Color base, int depth) {
  final hsl = HSLColor.fromColor(base);
  final lightness = math.min(0.72, hsl.lightness + depth * 0.1);
  return hsl.withLightness(lightness).toColor();
}

const double _levelWidthStep = 170;
const double _laneHeight = 64;

class _BranchNode {
  _BranchNode({required this.personId, required this.label, this.caption});

  final String personId;
  final String label;
  final String? caption;
}

class _Branch {
  _Branch({required this.color, required this.isRoute, required this.nodes});

  factory _Branch.fromRoute(AssistantRoute route, Color color) => _Branch(
        color: color,
        isRoute: true,
        nodes: [
          for (var i = 0; i < route.steps.length; i++)
            _BranchNode(
              personId: route.steps[i].personId,
              label: route.steps[i].personName,
              caption: i == 0 ? null : route.steps[i].relationTypeFromPrevious,
            ),
        ],
      );

  factory _Branch.fromHint(AssistantHint hint, Color color) => _Branch(
        color: color,
        isRoute: false,
        nodes: [
          _BranchNode(
            personId: hint.personId,
            label: hint.personName,
            caption: hint.reason.length > 16 ? '${hint.reason.substring(0, 16)}…' : hint.reason,
          ),
        ],
      );

  final Color color;
  final bool isRoute;
  final List<_BranchNode> nodes;
}

class _LayoutNode {
  _LayoutNode({
    required this.personId,
    required this.label,
    required this.caption,
    required this.position,
    required this.color,
    required this.isHint,
  });

  final String personId;
  final String label;
  final String? caption;
  Offset position;
  final Color color;
  final bool isHint;
}

class _LayoutEdge {
  _LayoutEdge({required this.from, required this.to, required this.color, required this.dashed});

  final Offset from;
  final Offset to;
  final Color color;
  final bool dashed;
}

/// おすすめの経路・関連しそうな人物を、自分を中心に左右2方向へ1件＝1レーンで並べるレイアウト。
/// 経路は複数人をつないだ実線のチェーン、ヒントは自分から直接伸びる点線の単一ノードとして描く。
class _DiagramLayout {
  _DiagramLayout({required List<AssistantRoute> routes, required List<AssistantHint> hints}) {
    final branches = <_Branch>[
      for (var i = 0; i < routes.length; i++) _Branch.fromRoute(routes[i], _palette[i % _palette.length]),
      for (var j = 0; j < hints.length; j++) _Branch.fromHint(hints[j], _palette[(routes.length + j) % _palette.length]),
    ];

    if (branches.isEmpty) return;

    // 人数（経路の長さ）が多いものから、その時点でレーン数の少ない側へ割り振り左右のバランスを取る。
    final sorted = [...branches]..sort((a, b) => b.nodes.length.compareTo(a.nodes.length));
    final rightBranches = <_Branch>[];
    final leftBranches = <_Branch>[];
    var rightLanes = 0;
    var leftLanes = 0;
    for (final branch in sorted) {
      if (rightLanes <= leftLanes) {
        rightBranches.add(branch);
        rightLanes++;
      } else {
        leftBranches.add(branch);
        leftLanes++;
      }
    }

    final rightStart = nodes.length;
    _cursor = 0;
    for (final branch in rightBranches) {
      _layoutBranch(branch, isLeft: false);
    }
    _shiftY(rightStart, nodes.length, -_cursor / 2);

    final leftStart = nodes.length;
    _cursor = 0;
    for (final branch in leftBranches) {
      _layoutBranch(branch, isLeft: true);
    }
    _shiftY(leftStart, nodes.length, -_cursor / 2);

    final maxX = nodes.isEmpty ? 0.0 : nodes.map((n) => n.position.dx.abs()).reduce(math.max);
    final maxY = nodes.isEmpty ? 0.0 : nodes.map((n) => n.position.dy.abs()).reduce(math.max);
    width = (maxX + 200) * 2;
    height = (maxY + 120) * 2;
  }

  final List<_LayoutNode> nodes = [];
  final List<_LayoutEdge> edges = [];
  double width = 500;
  double height = 400;
  double _cursor = 0;

  void _shiftY(int start, int end, double dy) {
    for (var i = start; i < end; i++) {
      nodes[i].position = nodes[i].position.translate(0, dy);
    }
  }

  void _layoutBranch(_Branch branch, {required bool isLeft}) {
    final y = _cursor;
    _cursor += _laneHeight;

    var from = Offset.zero;
    for (var depth = 1; depth <= branch.nodes.length; depth++) {
      final x = (isLeft ? -1.0 : 1.0) * depth * _levelWidthStep;
      final position = Offset(x, y);
      final branchNode = branch.nodes[depth - 1];
      nodes.add(_LayoutNode(
        personId: branchNode.personId,
        label: branchNode.label,
        caption: branchNode.caption,
        position: position,
        color: _shadeForDepth(branch.color, depth - 1),
        isHint: !branch.isRoute,
      ));
      edges.add(_LayoutEdge(from: from, to: position, color: branch.color, dashed: !branch.isRoute));
      from = position;
    }
  }
}

class _DiagramEdgePainter extends CustomPainter {
  _DiagramEdgePainter({required this.edges, required this.center});

  final List<_LayoutEdge> edges;
  final Offset center;

  @override
  void paint(Canvas canvas, Size size) {
    for (final edge in edges) {
      final from = center + edge.from;
      final to = center + edge.to;
      final path = Path()..moveTo(from.dx, from.dy);
      final midX = (from.dx + to.dx) / 2;
      path.cubicTo(midX, from.dy, midX, to.dy, to.dx, to.dy);

      final paint = Paint()
        ..color = edge.color.withValues(alpha: 0.6)
        ..strokeWidth = 2.2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      if (edge.dashed) {
        _drawDashedPath(canvas, path, paint);
      } else {
        canvas.drawPath(path, paint);
      }
    }
  }

  void _drawDashedPath(Canvas canvas, Path path, Paint paint, {double dashWidth = 6, double dashGap = 4}) {
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = math.min(distance + dashWidth, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + dashGap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DiagramEdgePainter oldDelegate) => oldDelegate.edges != edges;
}
