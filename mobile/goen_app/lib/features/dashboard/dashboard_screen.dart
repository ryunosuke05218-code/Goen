import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'dashboard_models.dart';
import 'dashboard_repository.dart';

final dashboardProvider = FutureProvider.autoDispose((ref) async {
  final repo = ref.watch(dashboardRepositoryProvider);
  return repo.get();
});

/// S-018 ダッシュボード画面（F-029）。自分の人脈の総人数・業種別/職種別の内訳・
/// 近い接点予定を一覧表示する。persons_read の集計のみでAIは使用しない。
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboardAsync = ref.watch(dashboardProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('ダッシュボード'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '再読み込み',
            onPressed: () => ref.invalidate(dashboardProvider),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: '設定',
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: dashboardAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, st) => Center(child: Text('読み込みに失敗しました: $err')),
        data: (data) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(dashboardProvider),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _TotalCountCard(totalCount: data.totalCount),
              const SizedBox(height: 16),
              _UpcomingContactsCard(contacts: data.upcomingContacts),
              const SizedBox(height: 16),
              _BreakdownCard(
                title: '業種別',
                entries: [for (final i in data.industryBreakdown) (label: i.industryName, count: i.count)],
              ),
              const SizedBox(height: 16),
              _BreakdownCard(
                title: '職種別',
                entries: [for (final o in data.occupationBreakdown) (label: o.occupationName, count: o.count)],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TotalCountCard extends StatelessWidget {
  const _TotalCountCard({required this.totalCount});

  final int totalCount;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(Icons.people_alt_outlined, size: 36, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('総登録人数', style: TextStyle(fontSize: 12, color: Colors.grey)),
                Text('$totalCount人', style: Theme.of(context).textTheme.headlineMedium),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _UpcomingContactsCard extends StatelessWidget {
  const _UpcomingContactsCard({required this.contacts});

  final List<UpcomingContact> contacts;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('近い接点予定', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            if (contacts.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('予定されている接点はありません', style: TextStyle(fontSize: 12, color: Colors.grey)),
              )
            else
              for (final c in contacts)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_outlined),
                  title: Text(c.content, maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text(c.personName),
                  trailing: c.dueDate == null ? null : Text(_formatDate(c.dueDate!)),
                  // 人物カルテ内の接点履歴セクションへ遷移する
                  onTap: () => context.push('/persons/${c.personId}'),
                ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) => '${date.month}/${date.day}';
}

class _BreakdownCard extends StatelessWidget {
  const _BreakdownCard({required this.title, required this.entries});

  final String title;
  final List<({String label, int count})> entries;

  @override
  Widget build(BuildContext context) {
    final maxCount = entries.isEmpty ? 1 : entries.map((e) => e.count).reduce((a, b) => a > b ? a : b);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (entries.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('データがありません', style: TextStyle(fontSize: 12, color: Colors.grey)),
              )
            else
              for (final e in entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 96,
                        child: Text(e.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: e.count / maxCount,
                            minHeight: 12,
                            backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 28,
                        child: Text('${e.count}', textAlign: TextAlign.right),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
