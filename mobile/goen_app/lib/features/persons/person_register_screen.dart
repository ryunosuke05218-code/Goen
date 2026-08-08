import 'package:flutter/material.dart';

import 'person_card_capture_screen.dart';
import 'person_manual_create_screen.dart';

enum _RegisterMode { card, manual }

/// S-002/S-003 人物登録画面。画面上部の切り替えボタンで「名刺で登録」「手入力で登録」を切り替える
/// （名刺撮影と手入力を別々のボタンで案内していたのを1つの入口に統合したもの）。
/// 両モードとも [IndexedStack] で保持するため、入力途中の内容は切り替えても消えない。
class PersonRegisterScreen extends StatefulWidget {
  const PersonRegisterScreen({super.key});

  @override
  State<PersonRegisterScreen> createState() => _PersonRegisterScreenState();
}

class _PersonRegisterScreenState extends State<PersonRegisterScreen> {
  _RegisterMode _mode = _RegisterMode.card;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('人物を登録'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: SegmentedButton<_RegisterMode>(
              segments: const [
                ButtonSegment(
                  value: _RegisterMode.card,
                  label: Text('名刺で登録'),
                  icon: Icon(Icons.add_a_photo_outlined),
                ),
                ButtonSegment(
                  value: _RegisterMode.manual,
                  label: Text('手入力で登録'),
                  icon: Icon(Icons.edit_outlined),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (selection) => setState(() => _mode = selection.first),
            ),
          ),
        ),
      ),
      body: IndexedStack(
        index: _mode == _RegisterMode.card ? 0 : 1,
        children: const [
          PersonCardCaptureScreen(),
          PersonManualCreateScreen(),
        ],
      ),
    );
  }
}
