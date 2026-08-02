import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../persons/models/person_models.dart';
import '../persons/person_repository.dart';
import 'graph_view.dart';

final myNetworkGraphProvider = FutureProvider.autoDispose((ref) async {
  final repo = ref.watch(personRepositoryProvider);
  return repo.getMyNetwork();
});

/// S-009 人脈マップ画面（F-005 人脈グラフ作成／F-006 人脈グラフ閲覧）。
/// 自分を中心としたマインドマップとして、直接の人脈(depth1)とその先の二次接点(depth2)を表示する。
class NetworkMapScreen extends ConsumerStatefulWidget {
  const NetworkMapScreen({super.key});

  @override
  ConsumerState<NetworkMapScreen> createState() => _NetworkMapScreenState();
}

class _NetworkMapScreenState extends ConsumerState<NetworkMapScreen> {
  NetworkGraphFilter? _filter;

  Future<void> _openFilter(NetworkGraph graph) async {
    final availableTypes = relationTypesIn(graph);
    final current = _filter ?? NetworkGraphFilter.all(graph);
    final updated = await showNetworkFilterSheet(context, current: current, availableTypes: availableTypes);
    if (updated != null) setState(() => _filter = updated);
  }

  @override
  Widget build(BuildContext context) {
    final graphAsync = ref.watch(myNetworkGraphProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('人脈マップ'),
        actions: [
          if (graphAsync.value case final graph?)
            IconButton(
              icon: const Icon(Icons.tune),
              tooltip: '表示フィルタ',
              onPressed: () => _openFilter(graph),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '再読み込み',
            onPressed: () => ref.invalidate(myNetworkGraphProvider),
          ),
        ],
      ),
      body: graphAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, st) => Center(child: Text('読み込みに失敗しました: $err')),
        data: (graph) {
          if (graph.nodes.length <= 1) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'まだ人物が登録されていません。\nホーム画面から名刺撮影や手入力で人物を登録すると、ここにマップが表示されます。',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final filter = _filter ?? NetworkGraphFilter.all(graph);
          final filteredGraph = filter.apply(graph);

          return Column(
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  'ピンチで拡大縮小、ノードをタップすると人物カルテを開きます。右上のアイコンで表示するつながりを絞り込めます。',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ),
              Expanded(
                child: GraphView(
                  graph: filteredGraph,
                  onNodeTap: (personId) => context.push('/persons/$personId'),
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.auto_awesome_outlined),
        label: const Text('AIに相談する'),
        onPressed: () => context.push('/network-map/ai-assistant'),
      ),
    );
  }
}
