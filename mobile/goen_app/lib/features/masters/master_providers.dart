import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../persons/models/person_models.dart';
import 'master_repository.dart';

/// 職種マスタ（Q-011解消）。人物登録・編集画面の選択肢、人脈図の階層グルーピングに使用。
final occupationTypesProvider = FutureProvider<List<OccupationTypeItem>>((ref) async {
  final repo = ref.watch(masterRepositoryProvider);
  return repo.listOccupationTypes();
});

/// 業種マスタ（F-030）。職種追加画面の業種選択肢、業種・職種管理画面に使用。
final industriesProvider = FutureProvider<List<IndustryItem>>((ref) async {
  final repo = ref.watch(masterRepositoryProvider);
  return repo.listIndustries();
});
