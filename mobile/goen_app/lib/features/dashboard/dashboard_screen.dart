import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../persons/person_repository.dart';
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
            onPressed: () => context.push('/settings', extra: '/home?tab=0'),
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
              const _SelfPersonCard(),
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

// 自分自身の人物カルテ（isSelf）の登録・編集導線。未登録時は登録ボタン、登録済みなら編集ボタンを出す。
class _SelfPersonCard extends ConsumerWidget {
  const _SelfPersonCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selfAsync = ref.watch(selfPersonProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: selfAsync.when(
          loading: () => const SizedBox(
            height: 24,
            child: Center(child: SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))),
          ),
          error: (err, st) => Text('自分の人物カルテの取得に失敗しました: $err', style: const TextStyle(fontSize: 12, color: Colors.grey)),
          data: (self) {
            if (self == null) {
              return Row(
                children: [
                  Icon(Icons.badge_outlined, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text('自分の人物カルテがまだ登録されていません', style: TextStyle(fontSize: 13)),
                  ),
                  FilledButton.tonal(
                    onPressed: () async {
                      final created = await context.push('/persons/me/new', extra: '/home?tab=0');
                      if (created != null) ref.invalidate(selfPersonProvider);
                    },
                    child: const Text('登録する'),
                  ),
                ],
              );
            }
            return Row(
              children: [
                CircleAvatar(
                  backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                  child: Icon(Icons.badge_outlined, color: Theme.of(context).colorScheme.onPrimaryContainer),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('自分の人物カルテ', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      Text(self.fullName, style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                OutlinedButton(
                  onPressed: () async {
                    final updated = await context.push<bool>('/persons/${self.personId}/edit', extra: (self, '/home?tab=0'));
                    if (updated == true) ref.invalidate(selfPersonProvider);
                  },
                  child: const Text('編集する'),
                ),
              ],
            );
          },
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
                  title: Text(
                    '${c.personName}（${_contactTypeLabel(c.contactType)}）',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: c.place == null ? null : Text(c.place!),
                  trailing: Text(_formatDate(c.occurredAt)),
                  // 人物カルテ内の接点履歴セクションへ遷移する
                  onTap: () => context.push('/persons/${c.personId}', extra: '/home?tab=0'),
                ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) => '${date.month}/${date.day}';
}

String _contactTypeLabel(String type) => switch (type) {
      'card_exchange' => '名刺交換',
      'one_on_one' => '1to1',
      'meeting' => '商談',
      'referral' => '紹介',
      'event' => 'イベント同席',
      _ => 'その他',
    };

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
