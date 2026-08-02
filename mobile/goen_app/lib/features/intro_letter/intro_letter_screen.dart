import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../persons/models/person_models.dart';
import '../persons/person_picker.dart';
import 'intro_letter_repository.dart';

const _toneOptions = ['丁寧', 'カジュアル', '熱意を込めて'];
const _lengthOptions = ['短め', '普通', '長め'];

/// S-014 紹介文作成画面（F-026）。通知機能（未実装のプレースホルダー）に代えて新設。
/// 対象人物・要件・その他条件を入力すると、その人物のDB上の実データ（AI要約・メモ・接点履歴等）を
/// もとにAIがそのまま送れるメッセージの下書きを1件作成する。
class IntroLetterScreen extends ConsumerStatefulWidget {
  const IntroLetterScreen({super.key});

  @override
  ConsumerState<IntroLetterScreen> createState() => _IntroLetterScreenState();
}

class _IntroLetterScreenState extends ConsumerState<IntroLetterScreen> {
  PersonListItem? _target;
  final _requirement = TextEditingController();
  final _additionalNotes = TextEditingController();
  String? _tone;
  String? _lengthHint;
  bool _isGenerating = false;
  String? _result;
  String? _error;

  @override
  void dispose() {
    _requirement.dispose();
    _additionalNotes.dispose();
    super.dispose();
  }

  Future<void> _pickTarget() async {
    final picked = await pickPerson(context, title: '相手を選択');
    if (picked != null) setState(() => _target = picked);
  }

  Future<void> _generate() async {
    final target = _target;
    if (target == null || _requirement.text.trim().isEmpty) return;

    setState(() {
      _isGenerating = true;
      _error = null;
    });
    try {
      final message = await ref.read(introLetterRepositoryProvider).generate(
            targetPersonId: target.personId,
            requirement: _requirement.text.trim(),
            tone: _tone,
            lengthHint: _lengthHint,
            additionalNotes: _additionalNotes.text.trim().isEmpty ? null : _additionalNotes.text.trim(),
          );
      if (!mounted) return;
      setState(() => _result = message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '作成に失敗しました: $e');
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  Future<void> _copyResult() async {
    if (_result == null) return;
    await Clipboard.setData(ClipboardData(text: _result!));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('コピーしました')));
  }

  bool get _canGenerate => _target != null && _requirement.text.trim().isNotEmpty && !_isGenerating;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('紹介文を作成')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            '相手・要件・条件を入力すると、その人物の登録済み情報（AI要約・メモ・接点履歴など）をもとに、'
            'AIがそのまま送れる文面を作成します。',
          ),
          const SizedBox(height: 16),
          Text('1. 相手', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          if (_target case final target?)
            Card(
              child: ListTile(
                title: Text(target.fullName),
                subtitle: Text([target.companyName, target.jobTitle].whereType<String>().where((e) => e.isNotEmpty).join(' / ')),
                trailing: IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _target = null)),
                onTap: _pickTarget,
              ),
            )
          else
            OutlinedButton.icon(
              icon: const Icon(Icons.person_search_outlined),
              label: const Text('相手を選択'),
              onPressed: _pickTarget,
            ),
          const SizedBox(height: 20),
          Text('2. 要件 *', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          TextField(
            controller: _requirement,
            minLines: 2,
            maxLines: 5,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: '例）新しく始めたサービスの導入を提案したい／久しぶりに近況を伺いたい',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          Text('3. その他の条件（任意）', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in _toneOptions)
                ChoiceChip(
                  label: Text(t),
                  selected: _tone == t,
                  onSelected: (selected) => setState(() => _tone = selected ? t : null),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final l in _lengthOptions)
                ChoiceChip(
                  label: Text(l),
                  selected: _lengthHint == l,
                  onSelected: (selected) => setState(() => _lengthHint = selected ? l : null),
                ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _additionalNotes,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: '例）来月のイベントへの招待も添えたい',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _canGenerate ? _generate : null,
            child: _isGenerating
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('作成する'),
          ),
          if (_isGenerating) ...[
            const SizedBox(height: 8),
            const Text(
              'AIが文面を作成しています…（ローカルAIのため1分ほどかかる場合があります）',
              style: TextStyle(fontSize: 12, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          if (_result case final result?) ...[
            const SizedBox(height: 20),
            Card(
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('作成された文面', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 8),
                    SelectableText(result),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          icon: const Icon(Icons.copy_outlined),
                          label: const Text('コピーする'),
                          onPressed: _copyResult,
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.refresh),
                          label: const Text('作成し直す'),
                          onPressed: _isGenerating ? null : _generate,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
