import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../home/main_bottom_nav_bar.dart';
import 'ai_assistant_repository.dart';
import 'ai_assistant_screen.dart';
import 'models/assistant_models.dart';

final _aiAssistantHistoryProvider = FutureProvider.autoDispose<List<AiAssistantHistoryItem>>((ref) {
  return ref.watch(aiAssistantRepositoryProvider).getHistory();
});

String _formatDateTime(DateTime dt) =>
    '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')} '
    '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

/// F-034: 過去のAI指示（人脈相談）の質問・回答を読み返すための一覧。人脈マップのAI指示画面から遷移する。
class AiAssistantHistoryScreen extends ConsumerWidget {
  const AiAssistantHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(_aiAssistantHistoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('AI相談の履歴')),
      body: historyAsync.when(
        data: (items) {
          if (items.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('まだAIに相談した履歴がありません。', textAlign: TextAlign.center),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () => ref.refresh(_aiAssistantHistoryProvider.future),
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(item.instruction, maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text(_formatDateTime(item.createdAt), style: const TextStyle(fontSize: 12)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => AiAssistantHistoryDetailScreen(item: item)),
                    ),
                  ),
                );
              },
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('履歴の取得に失敗しました: $e')),
      ),
      bottomNavigationBar: const MainBottomNavBar(selectedIndex: 3),
    );
  }
}

/// 過去のAI指示1件の質問・回答をそのまま読み返す詳細表示。入力フォームへの復元は行わない。
class AiAssistantHistoryDetailScreen extends StatelessWidget {
  const AiAssistantHistoryDetailScreen({super.key, required this.item});

  final AiAssistantHistoryItem item;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI相談の履歴')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(_formatDateTime(item.createdAt), style: const TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 8),
          Text('質問', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(item.instruction),
          const SizedBox(height: 20),
          AssistantResultView(
            result: AssistantResult(answer: item.answer, routes: item.routes, hints: item.hints),
          ),
        ],
      ),
      bottomNavigationBar: const MainBottomNavBar(selectedIndex: 3),
    );
  }
}
