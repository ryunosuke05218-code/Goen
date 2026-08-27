import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'models/person_models.dart';
import 'person_repository.dart';

typedef _ListQuery = ({String query, PersonSortOrder sort});

final personListProvider = FutureProvider.autoDispose.family<PersonListResponse, _ListQuery>((ref, params) async {
  final repo = ref.watch(personRepositoryProvider);
  return repo.list(query: params.query.isEmpty ? null : params.query, sort: params.sort);
});

/// S-007 人物一覧画面。F-003: ソート順切替・総登録人数の表示に対応。
class PersonListScreen extends ConsumerStatefulWidget {
  const PersonListScreen({super.key});

  @override
  ConsumerState<PersonListScreen> createState() => _PersonListScreenState();
}

class _PersonListScreenState extends ConsumerState<PersonListScreen> {
  String _query = '';
  PersonSortOrder _sort = PersonSortOrder.lastContact;

  @override
  Widget build(BuildContext context) {
    final params = (query: _query, sort: _sort);
    final personsAsync = ref.watch(personListProvider(params));
    final selfAsync = ref.watch(selfPersonProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('人物一覧'),
        actions: [
          PopupMenuButton<PersonSortOrder>(
            icon: const Icon(Icons.sort),
            tooltip: '並べ替え',
            initialValue: _sort,
            onSelected: (v) => setState(() => _sort = v),
            itemBuilder: (context) => [
              for (final order in PersonSortOrder.values)
                PopupMenuItem(value: order, child: Text(order.label)),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: '例）氏名・会社名・動画制作 京都 など',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 6, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '氏名がわからなくても、課題・事業内容などのキーワードであいまいに検索できます',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
          ),
          // 自分の人物カルテは通常の登録人物と混ざらないよう、検索・並べ替えの対象外として常に最上部に固定表示する。
          selfAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (err, st) => const SizedBox.shrink(),
            data: (self) {
              if (self == null) return const SizedBox.shrink();
              return Material(
                color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.35),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    child: Icon(Icons.badge_outlined, color: Theme.of(context).colorScheme.onPrimary),
                  ),
                  title: Text(self.fullName),
                  subtitle: Text([self.companyName, self.jobTitle]
                      .whereType<String>()
                      .where((e) => e.isNotEmpty)
                      .join(' / ')),
                  trailing: Chip(
                    label: const Text('自分', style: TextStyle(fontSize: 11)),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  // 人物一覧は'/home?tab=1'のタブとして開かれるため、通常のpop()に任せると
                  // タブの状態が正しく復元されないことがある。戻り先を明示的に指定する。
                  onTap: () => context.push('/persons/${self.personId}', extra: '/home?tab=1'),
                ),
              );
            },
          ),
          selfAsync.value != null ? const Divider(height: 1) : const SizedBox.shrink(),
          Expanded(
            child: personsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, st) => Center(child: Text('読み込みに失敗しました: $err')),
              data: (result) {
                final persons = result.items;
                if (persons.isEmpty) {
                  return const Center(child: Text('登録済みの人物がいません'));
                }
                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(personListProvider(params)),
                  child: ListView.separated(
                    itemCount: persons.length + 1,
                    separatorBuilder: (context, index) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Text(
                            '総登録人数: ${result.totalCount}人${_query.isNotEmpty ? '（絞り込み結果）' : ''}',
                            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline),
                          ),
                        );
                      }
                      final p = persons[index - 1];
                      return ListTile(
                        leading: CircleAvatar(child: Text(p.fullName.isEmpty ? '?' : p.fullName.substring(0, 1))),
                        title: Text(p.fullName),
                        subtitle: Text([p.companyName, p.jobTitle]
                            .whereType<String>()
                            .where((e) => e.isNotEmpty)
                            .join(' / ')),
                        onTap: () => context.push('/persons/${p.personId}', extra: '/home?tab=1'),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'person_list_fab',
        onPressed: () => context.push('/persons/new'),
        child: const Icon(Icons.add),
      ),
    );
  }
}
