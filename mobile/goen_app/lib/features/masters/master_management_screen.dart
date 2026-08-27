import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../home/main_bottom_nav_bar.dart';
import '../persons/models/person_models.dart';
import 'master_providers.dart';
import 'master_repository.dart';
import 'occupation_add_sheet.dart';

/// F-030: 業種・職種の管理画面。職種は名称の変更、紐づく業種の変更、有効/無効の切り替えができる。
/// 業種は固定の8種で運用するため、本画面からの追加・編集・削除はできない（一覧表示のみ）。
/// 職種は一覧から削除すると既存人物の参照が壊れるため、削除ではなく無効化（is_active）で運用する。
class MasterManagementScreen extends ConsumerWidget {
  const MasterManagementScreen({super.key});

  Future<void> _addOccupation(BuildContext context, WidgetRef ref) async {
    final created = await showAddOccupationSheet(context);
    if (created != null) ref.invalidate(occupationTypesProvider);
  }

  Future<void> _editOccupation(
    BuildContext context,
    WidgetRef ref,
    OccupationTypeItem occupation,
    List<IndustryItem> industries,
  ) async {
    final controller = TextEditingController(text: occupation.occupationName);
    final industryCodes = Set<String>.of(occupation.industryCodes);
    var isActive = occupation.isActive;
    final active = industries.where((i) => i.isActive || industryCodes.contains(i.industryCode)).toList();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('職種を編集'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: controller,
                  decoration: const InputDecoration(labelText: '職種名', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 16),
                const Text('業種（複数選択可）'),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final i in active)
                      FilterChip(
                        label: Text(i.industryName),
                        selected: industryCodes.contains(i.industryCode),
                        onSelected: (selected) => setDialogState(() {
                          if (selected) {
                            industryCodes.add(i.industryCode);
                          } else {
                            industryCodes.remove(i.industryCode);
                          }
                        }),
                      ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('有効'),
                  value: isActive,
                  onChanged: (v) => setDialogState(() => isActive = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('キャンセル')),
            FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('保存する')),
          ],
        ),
      ),
    );
    if (result != true) return;
    try {
      await ref.read(masterRepositoryProvider).updateOccupationType(
            occupationCode: occupation.occupationCode,
            occupationName: controller.text.trim(),
            industryCodes: industryCodes.toList(),
            isActive: isActive,
          );
      ref.invalidate(occupationTypesProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('職種の更新に失敗しました: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final industriesAsync = ref.watch(industriesProvider);
    final occupationsAsync = ref.watch(occupationTypesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('業種・職種の管理')),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('業種', style: Theme.of(context).textTheme.titleMedium),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(
              '業種は固定の一覧のため、追加・編集・削除はできません。',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
          industriesAsync.when(
            loading: () => const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()),
            error: (err, st) => Padding(padding: const EdgeInsets.all(16), child: Text('取得に失敗しました: $err')),
            data: (industries) => industries.isEmpty
                ? const Padding(padding: EdgeInsets.all(16), child: Text('業種が登録されていません'))
                : Column(
                    children: [
                      for (final industry in industries) ListTile(title: Text(industry.industryName)),
                    ],
                  ),
          ),
          const Divider(height: 32),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Row(
              children: [
                Text('職種', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                TextButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('追加'),
                  onPressed: () => _addOccupation(context, ref),
                ),
              ],
            ),
          ),
          occupationsAsync.when(
            loading: () => const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()),
            error: (err, st) => Padding(padding: const EdgeInsets.all(16), child: Text('取得に失敗しました: $err')),
            data: (occupations) => occupations.isEmpty
                ? const Padding(padding: EdgeInsets.all(16), child: Text('職種が登録されていません'))
                : Column(
                    children: [
                      for (final occupation in occupations)
                        ListTile(
                          title: Text(occupation.occupationName),
                          subtitle: Text(
                            [
                              occupation.industryNames.isEmpty ? '業種未設定' : occupation.industryNames.join('・'),
                              if (!occupation.isActive) '無効',
                            ].join(' / '),
                            style: const TextStyle(color: Colors.grey),
                          ),
                          trailing: const Icon(Icons.edit_outlined),
                          onTap: () => _editOccupation(
                            context,
                            ref,
                            occupation,
                            industriesAsync.value ?? const [],
                          ),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 24),
        ],
      ),
      bottomNavigationBar: const MainBottomNavBar(selectedIndex: 0),
    );
  }
}
