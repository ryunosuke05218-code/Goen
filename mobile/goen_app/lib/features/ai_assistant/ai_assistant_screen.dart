import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/bullet_text.dart';
import '../home/main_bottom_nav_bar.dart';
import '../intro_letter/intro_letter_screen.dart';
import '../persons/relation_type.dart';
import 'ai_assistant_history_screen.dart';
import 'ai_assistant_repository.dart';
import 'models/assistant_models.dart';

const _examplePrompts = [
  '〇〇会社と繋がりたいのですが、誰か紹介してもらえそうですか？',
  '去年、京都の交流会で会った人を思い出したい',
  '動画制作について相談できそうな人はいますか？',
];

/// 「AI指示」画面（人脈マップ→AIに相談する）。
/// 人脈マップ自体はAIを使わずつながりの線だけを表示するため、経路提案・RAG検索はこの画面に切り出す。
class AiAssistantScreen extends ConsumerStatefulWidget {
  const AiAssistantScreen({super.key, this.returnPath});

  // 戻るボタンで明示的に戻したい遷移元（例: 人脈マップの'/home?tab=3'）。未指定時は通常のpop()に任せる。
  final String? returnPath;

  @override
  ConsumerState<AiAssistantScreen> createState() => _AiAssistantScreenState();
}

class _AiAssistantScreenState extends ConsumerState<AiAssistantScreen> {
  final _controller = TextEditingController();
  bool _isLoading = false;
  String? _error;
  AssistantResult? _result;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final instruction = _controller.text.trim();
    if (instruction.isEmpty) return;

    setState(() {
      _isLoading = true;
      _error = null;
      _result = null;
    });

    try {
      final result = await ref.read(aiAssistantRepositoryProvider).query(instruction);
      if (!mounted) return;
      setState(() => _result = result);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '検索に失敗しました: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: widget.returnPath == null
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: '戻る',
                onPressed: () => context.go(widget.returnPath!),
              ),
        title: const Text('AIに相談する'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: '過去の相談履歴',
            onPressed: () => context.push('/network-map/ai-assistant/history'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'つながりたい会社や、あいまいな記憶の人脈について、自然な文章で質問してください。'
            '登録済みの人脈データ（メモ・都道府県・紹介関係など）をもとに、AIが経路やヒントを提案します。',
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final example in _examplePrompts)
                ActionChip(
                  label: Text(example, style: const TextStyle(fontSize: 12)),
                  onPressed: () => setState(() => _controller.text = example),
                ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: '例）〇〇会社の担当者と繋がりたいのですが…',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            icon: const Icon(Icons.auto_awesome_outlined),
            label: const Text('AIに質問する'),
            onPressed: _isLoading ? null : _submit,
          ),
          const SizedBox(height: 20),
          if (_isLoading)
            const Center(
              child: Column(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text(
                    'AIが考えています…（ローカルAIのため1分ほどかかる場合があります）',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          if (_result case final result?) AssistantResultView(key: ObjectKey(result), result: result),
        ],
      ),
      bottomNavigationBar: const MainBottomNavBar(selectedIndex: 3),
    );
  }
}

/// AIの回答・経路・関連人物を表示するビュー。
/// 現在の相談結果（[AiAssistantScreen]）と、過去の履歴詳細（[AiAssistantHistoryDetailScreen]）の両方から共用する。
class AssistantResultView extends StatelessWidget {
  const AssistantResultView({super.key, required this.result});

  final AssistantResult result;

  @override
  Widget build(BuildContext context) {
    final hasResults = result.routes.isNotEmpty || result.hints.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          color: Theme.of(context).colorScheme.secondaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.auto_awesome_outlined, size: 18),
                    const SizedBox(width: 6),
                    Text('AIの回答', style: Theme.of(context).textTheme.titleSmall),
                  ],
                ),
                const SizedBox(height: 8),
                BulletText(result.answer),
              ],
            ),
          ),
        ),
        if (hasResults) ...[
          const SizedBox(height: 16),
          if (result.routes.isNotEmpty) ...[
            Text('おすすめの経路', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final route in result.routes) _RouteChain(route: route),
          ],
          if (result.hints.isNotEmpty) ...[
            if (result.routes.isNotEmpty) const SizedBox(height: 16),
            Text('関連しそうな人物', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            for (final hint in result.hints) _HintTile(hint: hint),
          ],
        ] else ...[
          const SizedBox(height: 16),
          const Text('具体的な経路・関連人物は見つかりませんでした。上の回答文を参考にしてください。',
              style: TextStyle(color: Colors.grey)),
        ],
      ],
    );
  }
}

class _RouteChain extends StatelessWidget {
  const _RouteChain({required this.route});

  final AssistantRoute route;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (var i = 0; i < route.steps.length; i++) ...[
              if (i > 0) _RouteArrow(relationType: route.steps[i].relationTypeFromPrevious),
              ActionChip(
                label: Text(route.steps[i].personName),
                onPressed: () => context.push('/persons/${route.steps[i].personId}'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RouteArrow extends StatelessWidget {
  const _RouteArrow({this.relationType});

  final String? relationType;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (relationType != null)
            Text(RelationTypeStyle.label(relationType!), style: const TextStyle(fontSize: 10, color: Colors.grey)),
          const Icon(Icons.arrow_forward, size: 16),
        ],
      ),
    );
  }
}

class _HintTile extends StatelessWidget {
  const _HintTile({required this.hint});

  final AssistantHint hint;

  // F-031: AI指示の提案理由・抜粋を、紹介文作成画面の「要件」欄の下書きとして引き継ぐ
  String get _requirementDraft => 'AI指示での相談を踏まえて連絡したい。\n提案理由: ${hint.reason}\n${hint.excerpt}';

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        title: Text(hint.personName),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(hint.reason, style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 12)),
            const SizedBox(height: 2),
            Text(hint.excerpt, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.edit_note, size: 16),
                label: const Text('この人への紹介文を作成', style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () => context.push(
                  '/intro-letter',
                  extra: IntroLetterPrefill(
                    personId: hint.personId,
                    personName: hint.personName,
                    requirement: _requirementDraft,
                  ),
                ),
              ),
            ),
          ],
        ),
        isThreeLine: true,
        onTap: () => context.push('/persons/${hint.personId}'),
      ),
    );
  }
}
