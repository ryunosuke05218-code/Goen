import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../persons/models/person_models.dart';

final masterRepositoryProvider = Provider<MasterRepository>((ref) {
  return MasterRepository(ref.watch(apiClientProvider).dio);
});

/// 業種（m_industry）・職種（m_occupation_type）マスタの参照・管理（F-030）
class MasterRepository {
  MasterRepository(this._dio);
  final Dio _dio;

  Future<List<IndustryItem>> listIndustries() async {
    final response = await _dio.get('/api/masters/industries');
    return (response.data as List).map((e) => IndustryItem.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<OccupationTypeItem>> listOccupationTypes() async {
    final response = await _dio.get('/api/masters/occupation-types');
    return (response.data as List).map((e) => OccupationTypeItem.fromJson(e as Map<String, dynamic>)).toList();
  }

  // 業種は固定8種からの複数選択（新規業種の作成は不可）
  Future<OccupationTypeItem> createOccupationType({
    required String occupationName,
    required List<String> industryCodes,
  }) async {
    final response = await _dio.post('/api/masters/occupation-types', data: {
      'occupationName': occupationName,
      'industryCodes': industryCodes,
    });
    return OccupationTypeItem.fromJson(response.data as Map<String, dynamic>);
  }

  Future<OccupationTypeItem> updateOccupationType({
    required String occupationCode,
    required String occupationName,
    required List<String> industryCodes,
    required bool isActive,
  }) async {
    final response = await _dio.put('/api/masters/occupation-types/$occupationCode', data: {
      'occupationName': occupationName,
      'industryCodes': industryCodes,
      'isActive': isActive,
    });
    return OccupationTypeItem.fromJson(response.data as Map<String, dynamic>);
  }
}
