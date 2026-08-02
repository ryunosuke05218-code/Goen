import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'person_repository.dart';

/// S-005 音声メモ入力画面（F-009）。
/// 実機マイク録音の連携は今後のフェーズで追加する。現段階では業務ルールに定める
/// 「テキストによる直接入力（代替手段）」のみをサポートし、接点ログとして保存する。
class VoiceMemoScreen extends ConsumerStatefulWidget {
  const VoiceMemoScreen({super.key, required this.personId});

  final String personId;

  @override
  ConsumerState<VoiceMemoScreen> createState() => _VoiceMemoScreenState();
}

class _VoiceMemoScreenState extends ConsumerState<VoiceMemoScreen> {
  final _memoController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _memoController.dispose();
    super.dispose();
  }

  Future<void> _saveAndGenerateCard() async {
    setState(() => _isSubmitting = true);
    try {
      final repo = ref.read(personRepositoryProvider);
      await repo.addContact(
        personId: widget.personId,
        contactType: 'card_exchange',
        occurredAt: DateTime.now(),
        note: _memoController.text.trim().isEmpty ? null : _memoController.text.trim(),
      );
      await repo.generateCard(widget.personId); // F-010: 蓄積情報からAI人物カルテを生成
      if (!mounted) return;
      context.pushReplacement('/persons/${widget.personId}');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存に失敗しました: $e')));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _skip() async {
    context.pushReplacement('/persons/${widget.personId}');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('音声メモ')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('出会いの直後に、事業内容・課題・紹介者・次回アクション・趣味などを一言で残しましょう（30秒目安）。'),
            const SizedBox(height: 4),
            const Text('※マイク録音は今後のフェーズで対応予定です。現在はテキスト入力で代替できます。',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 16),
            TextField(
              controller: _memoController,
              maxLines: 6,
              decoration: const InputDecoration(
                hintText: '例）動画制作会社を探していた。紹介者は鈴木さん。来週水曜フォロー予定。',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _isSubmitting ? null : _saveAndGenerateCard,
              child: _isSubmitting
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('保存してAIカルテを生成'),
            ),
            TextButton(
              onPressed: _isSubmitting ? null : _skip,
              child: const Text('スキップ'),
            ),
          ],
        ),
      ),
    );
  }
}
