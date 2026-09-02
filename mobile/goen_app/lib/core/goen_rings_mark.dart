import 'dart:math' as math;

import 'package:flutter/material.dart';

/// ロゴの「三つ輪」をモチーフにした装飾グラフィック。人と人のつながり（ご縁）を表す三つの輪を、
/// 三角形の頂点に配置して少しずつ重ねて描く。スプラッシュ画面やホーム/ダッシュボードのヘッダーなど、
/// 画像アセットを増やさずに軽量にブランドの雰囲気を出したい箇所で使う。
class GoenRingsMark extends StatelessWidget {
  const GoenRingsMark({super.key, this.size = 96, this.color, this.strokeWidthRatio = 0.16});

  final double size;
  final Color? color;
  final double strokeWidthRatio;

  @override
  Widget build(BuildContext context) {
    final ringColor = color ?? Theme.of(context).colorScheme.primary;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingsPainter(color: ringColor, strokeWidthRatio: strokeWidthRatio),
      ),
    );
  }
}

class _RingsPainter extends CustomPainter {
  _RingsPainter({required this.color, required this.strokeWidthRatio});

  final Color color;
  final double strokeWidthRatio;

  @override
  void paint(Canvas canvas, Size size) {
    final ringDiameter = size.shortestSide * 0.62;
    final strokeWidth = ringDiameter * strokeWidthRatio;
    final radius = ringDiameter / 2;
    final center = Offset(size.width / 2, size.height / 2);
    // 中心から三方向（上・左下・右下）へオフセットして三つの輪を少しずつ重ねる。
    final offset = radius * 0.62;
    final centers = [
      center + Offset(0, -offset),
      center + Offset(-offset * math.cos(math.pi / 6), offset * math.sin(math.pi / 6)),
      center + Offset(offset * math.cos(math.pi / 6), offset * math.sin(math.pi / 6)),
    ];

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    for (final c in centers) {
      canvas.drawCircle(c, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RingsPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.strokeWidthRatio != strokeWidthRatio;
}
