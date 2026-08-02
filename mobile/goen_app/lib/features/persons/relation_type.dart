import 'package:flutter/material.dart';

/// 人脈関係の種別（referrer/community/self）に対する
/// 表示ラベル・色を一箇所にまとめる（人脈グラフの描画・凡例・AI提案ダイアログで共用）。
/// 同僚・取引先等の組織上・取引上の文脈情報はエッジ化せず人物カルテのメモ（RAG検索対象）で持つ。
class RelationTypeStyle {
  static const _labels = {
    'referrer': '紹介者',
    'community': '人脈・知人',
    'self': '自分の人脈',
  };

  static const _colors = {
    'referrer': Color(0xFF3B82F6), // blue
    'community': Color(0xFF14B8A6), // teal
    'other': Color(0xFF9CA3AF), // grey
    'self': Color(0xFFB0B7C3), // 中心からの合成エッジ用の淡いグレー
  };

  static String label(String type) => _labels[type] ?? 'その他';

  static Color color(String type) => _colors[type] ?? _colors['other']!;
}
