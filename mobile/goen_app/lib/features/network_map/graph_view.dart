import 'package:flutter/material.dart';

import '../persons/models/person_models.dart';
import '../persons/relation_type.dart';

/// グラフに含まれる関係種別の一覧（"self"の合成エッジは表示切替の対象外のため除く）
Set<String> relationTypesIn(NetworkGraph graph) =>
    graph.edges.map((e) => e.relationType).where((t) => t != 'self').toSet();

/// どの関係種別・深さのつながりを表示するかのフィルタ設定。
/// depth0（自分）・depth1（直接の人脈）は常に表示し、depth2（二次接点）と関係種別のみ絞り込む。
class NetworkGraphFilter {
  const NetworkGraphFilter({required this.visibleTypes, this.showSecondDegree = true});

  final Set<String> visibleTypes;
  final bool showSecondDegree;

  factory NetworkGraphFilter.all(NetworkGraph graph) =>
      NetworkGraphFilter(visibleTypes: relationTypesIn(graph));

  NetworkGraphFilter copyWith({Set<String>? visibleTypes, bool? showSecondDegree}) => NetworkGraphFilter(
        visibleTypes: visibleTypes ?? this.visibleTypes,
        showSecondDegree: showSecondDegree ?? this.showSecondDegree,
      );

  NetworkGraph apply(NetworkGraph graph) {
    final depth2Ids = graph.nodes.where((n) => n.depth >= 2).map((n) => n.personId).toSet();
    final alwaysVisibleIds = graph.nodes.where((n) => n.depth <= 1).map((n) => n.personId).toSet();

    final filteredEdges = graph.edges.where((e) {
      if (e.relationType != 'self' && !visibleTypes.contains(e.relationType)) return false;
      if (!showSecondDegree && (depth2Ids.contains(e.fromPersonId) || depth2Ids.contains(e.toPersonId))) {
        return false;
      }
      return true;
    }).toList();

    final visibleIds = {...alwaysVisibleIds};
    if (showSecondDegree) {
      for (final e in filteredEdges) {
        visibleIds.add(e.fromPersonId);
        visibleIds.add(e.toPersonId);
      }
    }

    return NetworkGraph(
      nodes: graph.nodes.where((n) => visibleIds.contains(n.personId)).toList(),
      edges: filteredEdges.where((e) => visibleIds.contains(e.fromPersonId) && visibleIds.contains(e.toPersonId)).toList(),
    );
  }
}

/// 表示フィルタ（関係種別・二次接点の有無）を選ぶボトムシート
Future<NetworkGraphFilter?> showNetworkFilterSheet(
  BuildContext context, {
  required NetworkGraphFilter current,
  required Set<String> availableTypes,
}) {
  return showModalBottomSheet<NetworkGraphFilter>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _NetworkFilterSheet(initial: current, availableTypes: availableTypes),
  );
}

class _NetworkFilterSheet extends StatefulWidget {
  const _NetworkFilterSheet({required this.initial, required this.availableTypes});

  final NetworkGraphFilter initial;
  final Set<String> availableTypes;

  @override
  State<_NetworkFilterSheet> createState() => _NetworkFilterSheetState();
}

class _NetworkFilterSheetState extends State<_NetworkFilterSheet> {
  late Set<String> _visibleTypes = {...widget.initial.visibleTypes};
  late bool _showSecondDegree = widget.initial.showSecondDegree;

  @override
  Widget build(BuildContext context) {
    final sortedTypes = widget.availableTypes.toList()..sort();

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('表示するつながり', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          const Text('チェックを外すと、その種類の線とノードを非表示にできます', style: TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 12),
          if (sortedTypes.isEmpty)
            const Text('まだ人脈同士のつながりが登録されていません')
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final type in sortedTypes)
                  FilterChip(
                    label: Text(RelationTypeStyle.label(type)),
                    avatar: CircleAvatar(backgroundColor: RelationTypeStyle.color(type), radius: 6),
                    selected: _visibleTypes.contains(type),
                    onSelected: (selected) => setState(() {
                      if (selected) {
                        _visibleTypes.add(type);
                      } else {
                        _visibleTypes.remove(type);
                      }
                    }),
                  ),
              ],
            ),
          const Divider(height: 32),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('二次的なつながりも表示'),
            subtitle: const Text('OFFにすると、直接の人脈のみのシンプルな表示になります'),
            value: _showSecondDegree,
            onChanged: (v) => setState(() => _showSecondDegree = v),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => setState(() {
                    _visibleTypes = {...widget.availableTypes};
                    _showSecondDegree = true;
                  }),
                  child: const Text('すべて表示'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(
                    NetworkGraphFilter(visibleTypes: _visibleTypes, showSecondDegree: _showSecondDegree),
                  ),
                  child: const Text('この条件で表示'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
