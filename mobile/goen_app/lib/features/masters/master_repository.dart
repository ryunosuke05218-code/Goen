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

  Future<IndustryItem> createIndustry(String industryName) async {
    final response = await _dio.post('/api/masters/industries', data: {'industryName': industryName});
    return IndustryItem.fromJson(response.data as Map<String, dynamic>);
  }

  Future<IndustryItem> updateIndustry({
    required String industryCode,
    required String industryName,
    required bool isActive,
  }) async {
    final response = await _dio.put('/api/masters/industries/$industryCode', data: {
      'industryName': industryName,
      'isActive': isActive,
    });
    return IndustryItem.fromJson(response.data as Map<String, dynamic>);
  }

  Future<List<OccupationTypeItem>> listOccupationTypes() async {
    final response = await _dio.get('/api/masters/occupation-types');
    return (response.data as List).map((e) => OccupationTypeItem.fromJson(e as Map<String, dynamic>)).toList();
  }

  // industryCode（既存の業種を選択）かnewIndustryName（新規作成）のどちらかを指定する
  Future<OccupationTypeItem> createOccupationType({
    required String occupationName,
    String? industryCode,
    String? newIndustryName,
  }) async {
    final response = await _dio.post('/api/masters/occupation-types', data: {
      'occupationName': occupationName,
      'industryCode': industryCode,
      'newIndustryName': newIndustryName,
    });
    return OccupationTypeItem.fromJson(response.data as Map<String, dynamic>);
  }

  Future<OccupationTypeItem> updateOccupationType({
    required String occupationCode,
    required String occupationName,
    String? industryCode,
    required bool isActive,
  }) async {
    final response = await _dio.put('/api/masters/occupation-types/$occupationCode', data: {
      'occupationName': occupationName,
      'industryCode': industryCode,
      'isActive': isActive,
    });
    return OccupationTypeItem.fromJson(response.data as Map<String, dynamic>);
  }
}
