import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../network_map/graph_view.dart';
import 'models/person_models.dart';
import 'person_repository.dart';

final personNetworkGraphProvider = FutureProvider.autoDispose.family((ref, String personId) async {
  final repo = ref.watch(personRepositoryProvider);
  return repo.getNetwork(personId);
});

/// 特定人物を起点とした人脈マップ（人物カルテの「人脈グラフを見る」から遷移）。
/// 表示自体は自分中心マップ（S-009）と同じ GraphView を再利用する。
class PersonNetworkScreen extends ConsumerStatefulWidget {
  const PersonNetworkScreen({super.key, required this.rootPersonId});

  final String rootPersonId;

  @override
  ConsumerState<PersonNetworkScreen> createState() => _PersonNetworkScreenState();
}

class _PersonNetworkScreenState extends ConsumerState<PersonNetworkScreen> {
  NetworkGraphFilter? _filter;

  Future<void> _openFilter(NetworkGraph graph) async {
    final availableTypes = relationTypesIn(graph);
    final current = _filter ?? NetworkGraphFilter.all(graph);
    final updated = await showNetworkFilterSheet(context, current: current, availableTypes: availableTypes);
    if (updated != null) setState(() => _filter = updated);
  }

  @override
  Widget build(BuildContext context) {
    final graphAsync = ref.watch(personNetworkGraphProvider(widget.rootPersonId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('この人物の人脈マップ'),
        actions: [
          if (graphAsync.value case final graph?)
            IconButton(
              icon: const Icon(Icons.tune),
              tooltip: '表示フィルタ',
              onPressed: () => _openFilter(graph),
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
                child: Text('この人物にはまだ人脈関係が登録されていません。\n人物カルテの「AIに関係性を提案してもらう」から関係を追加できます。', textAlign: TextAlign.center),
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
                  centerPersonId: widget.rootPersonId,
                  onNodeTap: (personId) => context.push('/persons/$personId'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
