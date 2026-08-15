import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../home/main_bottom_nav_bar.dart';
import 'intro_letter_repository.dart';

final _introLetterHistoryProvider = FutureProvider.autoDispose<List<IntroLetterHistoryItem>>((ref) {
  return ref.watch(introLetterRepositoryProvider).getHistory();
});

String _formatDateTime(DateTime dt) =>
    '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')} '
    '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

/// F-034: 過去の紹介文作成の依頼・生成結果を読み返すための一覧。紹介文作成画面から遷移する。
class IntroLetterHistoryScreen extends ConsumerWidget {
  const IntroLetterHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(_introLetterHistoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('紹介文作成の履歴')),
      body: historyAsync.when(
        data: (items) {
          if (items.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('まだ紹介文を作成した履歴がありません。', textAlign: TextAlign.center),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () => ref.refresh(_introLetterHistoryProvider.future),
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(item.targetPersonName),
                    subtitle: Text(
                      '${item.requirement}\n${_formatDateTime(item.createdAt)}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    isThreeLine: true,
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => IntroLetterHistoryDetailScreen(item: item)),
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
      bottomNavigationBar: const MainBottomNavBar(selectedIndex: 4),
    );
  }
}

/// 過去の紹介文作成1件の依頼内容・生成結果をそのまま読み返す詳細表示。入力フォームへの復元は行わない。
class IntroLetterHistoryDetailScreen extends StatelessWidget {
  const IntroLetterHistoryDetailScreen({super.key, required this.item});

  final IntroLetterHistoryItem item;

  Future<void> _copyResult(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: item.generatedMessage));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('コピーしました')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('紹介文作成の履歴')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(_formatDateTime(item.createdAt), style: const TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 8),
          Text('相手', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(item.targetPersonName),
          const SizedBox(height: 16),
          Text('要件', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(item.requirement),
          if (item.tone != null || item.lengthHint != null || item.additionalNotes != null) ...[
            const SizedBox(height: 16),
            Text('その他の条件', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            if (item.tone != null) Text('トーン: ${item.tone}'),
            if (item.lengthHint != null) Text('文字数目安: ${item.lengthHint}'),
            if (item.additionalNotes != null) Text(item.additionalNotes!),
          ],
          if (item.hpUrl != null || item.attachedFileName != null) ...[
            const SizedBox(height: 16),
            Text('参考情報', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            if (item.hpUrl != null) Text('HPリンク: ${item.hpUrl}'),
            if (item.attachedFileName != null) Text('添付ファイル: ${item.attachedFileName}'),
          ],
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
                  SelectableText(item.generatedMessage),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.copy_outlined),
                    label: const Text('コピーする'),
                    onPressed: () => _copyResult(context),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: const MainBottomNavBar(selectedIndex: 4),
    );
  }
}
