import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../persons/models/person_models.dart';
import '../persons/person_repository.dart';

final orgMembersProvider = FutureProvider.autoDispose((ref) async {
  final repo = ref.watch(personRepositoryProvider);
  return repo.listOrgMembers();
});

final industrySummaryProvider =
    FutureProvider.autoDispose.family<IndustryBreakdown, String>((ref, userId) async {
  final repo = ref.watch(personRepositoryProvider);
  return repo.getIndustrySummary(userId);
});

/// F-027: 同一組織内の他ユーザーの人脈図を、業種階層まで（人数集計のみ）で閲覧する。
/// 職種・会社名・人物といった詳細は一切取得・表示しない。
class OtherUserNetworkScreen extends ConsumerStatefulWidget {
  const OtherUserNetworkScreen({super.key});

  @override
  ConsumerState<OtherUserNetworkScreen> createState() => _OtherUserNetworkScreenState();
}

class _OtherUserNetworkScreenState extends ConsumerState<OtherUserNetworkScreen> {
  OrgMember? _selected;

  @override
  Widget build(BuildContext context) {
    final membersAsync = ref.watch(orgMembersProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('他ユーザーの人脈図')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '同じ組織のメンバーを選ぶと、業種ごとの人数だけを確認できます。個々の人物・職種・会社名などの詳細は表示されません。',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            membersAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (err, st) => Text('メンバー一覧の取得に失敗しました: $err'),
              data: (members) {
                if (members.isEmpty) {
                  return const Text('同じ組織の他のメンバーがいません');
                }
                return DropdownButtonFormField<OrgMember>(
                  initialValue: _selected,
                  decoration: const InputDecoration(labelText: 'メンバーを選択', border: OutlineInputBorder()),
                  items: [
                    for (final m in members) DropdownMenuItem(value: m, child: Text(m.displayName)),
                  ],
                  onChanged: (v) => setState(() => _selected = v),
                );
              },
            ),
            const SizedBox(height: 24),
            if (_selected case final selected?)
              Expanded(child: _IndustrySummaryView(userId: selected.userId)),
          ],
        ),
      ),
    );
  }
}

class _IndustrySummaryView extends ConsumerWidget {
  const _IndustrySummaryView({required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(industrySummaryProvider(userId));

    return summaryAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, st) => Center(child: Text('取得に失敗しました: $err')),
      data: (summary) {
        if (summary.totalCount == 0) {
          return const Center(child: Text('登録なし'));
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${summary.targetUserDisplayName}さんの人脈（総数: ${summary.totalCount}人）',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.separated(
                itemCount: summary.industries.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final industry = summary.industries[index];
                  return ListTile(
                    leading: const Icon(Icons.domain_outlined),
                    title: Text(industry.industryName),
                    trailing: Text('${industry.count}人', style: const TextStyle(fontWeight: FontWeight.bold)),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
