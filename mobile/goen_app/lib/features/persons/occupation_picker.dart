import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/person_models.dart';
import 'person_repository.dart';

/// 職種マスタ（Q-011解消）。アプリ起動中は変化しない前提でキャッシュする。
final occupationTypesProvider = FutureProvider<List<OccupationTypeItem>>((ref) async {
  final repo = ref.watch(personRepositoryProvider);
  return repo.listOccupationTypes();
});

/// 職種（F-006の人脈図の階層グルーピングに使用）の選択欄。人物登録・編集画面で共通利用する。
class OccupationDropdown extends ConsumerWidget {
  const OccupationDropdown({super.key, required this.value, required this.onChanged});

  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final occupationsAsync = ref.watch(occupationTypesProvider);

    return occupationsAsync.when(
      loading: () => const LinearProgressIndicator(),
      error: (err, st) => const SizedBox.shrink(), // 職種マスタが取得できなくても他の項目の入力は妨げない
      data: (occupations) => DropdownButtonFormField<String?>(
        initialValue: occupations.any((o) => o.occupationCode == value) ? value : null,
        decoration: const InputDecoration(
          labelText: '職種',
          border: OutlineInputBorder(),
          helperText: '人脈図（人脈マップ）のグルーピングに使用します',
        ),
        items: [
          const DropdownMenuItem<String?>(value: null, child: Text('未設定')),
          for (final o in occupations)
            DropdownMenuItem<String?>(value: o.occupationCode, child: Text(o.occupationName)),
        ],
        onChanged: onChanged,
      ),
    );
  }
}
