import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'models/person_models.dart';
import 'person_repository.dart';

final personListProvider = FutureProvider.autoDispose.family<List<PersonListItem>, String>((ref, query) async {
  final repo = ref.watch(personRepositoryProvider);
  return repo.list(query: query.isEmpty ? null : query);
});

/// S-007 人物一覧画面
class PersonListScreen extends ConsumerStatefulWidget {
  const PersonListScreen({super.key});

  @override
  ConsumerState<PersonListScreen> createState() => _PersonListScreenState();
}

class _PersonListScreenState extends ConsumerState<PersonListScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final personsAsync = ref.watch(personListProvider(_query));

    return Scaffold(
      appBar: AppBar(
        title: const Text('人物一覧'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: '氏名・会社名で絞り込み',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: personsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, st) => Center(child: Text('読み込みに失敗しました: $err')),
              data: (persons) {
                if (persons.isEmpty) {
                  return const Center(child: Text('登録済みの人物がいません'));
                }
                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(personListProvider(_query)),
                  child: ListView.separated(
                    itemCount: persons.length,
                    separatorBuilder: (context, index) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final p = persons[index];
                      return ListTile(
                        leading: CircleAvatar(child: Text(_star(p.importance))),
                        title: Text(p.fullName),
                        subtitle: Text([p.companyName, p.jobTitle]
                            .whereType<String>()
                            .where((e) => e.isNotEmpty)
                            .join(' / ')),
                        onTap: () => context.push('/persons/${p.personId}'),
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
        onPressed: () => context.push('/persons/new/manual'),
        child: const Icon(Icons.add),
      ),
    );
  }

  String _star(int importance) => '★$importance';
}
