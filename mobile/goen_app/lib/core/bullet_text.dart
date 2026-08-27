import 'package:flutter/material.dart';

/// AIが生成した要約テキストを表示する共通ウィジェット。
/// 「・」「-」「•」で始まる複数行は箇条書きとして見やすく整形し、それ以外（旧形式の文章など）は
/// 通常の段落テキストとしてそのまま表示する。
class BulletText extends StatelessWidget {
  const BulletText(this.text, {super.key, this.style});

  final String text;
  final TextStyle? style;

  static final _bulletPrefix = RegExp(r'^[・\-•]\s*');

  @override
  Widget build(BuildContext context) {
    final lines = text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    final isBulletList = lines.length > 1 && lines.every((l) => _bulletPrefix.hasMatch(l));

    if (!isBulletList) {
      return Text(text, style: style);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('・${line.replaceFirst(_bulletPrefix, '')}', style: style),
          ),
      ],
    );
  }
}
