import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import 'models/person_models.dart';

final personRepositoryProvider = Provider<PersonRepository>((ref) {
  return PersonRepository(ref.watch(apiClientProvider).dio);
});

class PersonRepository {
  PersonRepository(this._dio);
  final Dio _dio;

  Future<List<PersonListItem>> list({String? query}) async {
    final response = await _dio.get('/api/persons', queryParameters: {
      if (query != null && query.isNotEmpty) 'q': query,
    });
    return (response.data as List).map((e) => PersonListItem.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<PersonDetail> get(String personId) async {
    final response = await _dio.get('/api/persons/$personId');
    return PersonDetail.fromJson(response.data as Map<String, dynamic>);
  }

  Future<PersonDetail> create({
    required String fullName,
    String? fullNameKana,
    String? department,
    String? jobTitle,
    String? companyName,
    String? tel,
    String? mobile,
    String? email,
    String? address,
    String? note,
    String sourceType = 'manual',
    String? introducerPersonId,
  }) async {
    final response = await _dio.post('/api/persons', data: {
      'fullName': fullName,
      'fullNameKana': fullNameKana,
      'department': department,
      'jobTitle': jobTitle,
      'companyName': companyName,
      'tel': tel,
      'mobile': mobile,
      'email': email,
      'address': address,
      'note': note,
      'sourceType': sourceType,
      'introducerPersonId': introducerPersonId,
    });
    return PersonDetail.fromJson(response.data as Map<String, dynamic>);
  }

  Future<PersonDetail> update({
    required String personId,
    required String fullName,
    String? fullNameKana,
    String? department,
    String? jobTitle,
    String? companyName,
    required int importance,
    required bool importanceIsManual,
    required String visibility,
    String? tel,
    String? mobile,
    String? email,
    String? address,
    String? note,
  }) async {
    final response = await _dio.put('/api/persons/$personId', data: {
      'fullName': fullName,
      'fullNameKana': fullNameKana,
      'department': department,
      'jobTitle': jobTitle,
      'companyName': companyName,
      'importance': importance,
      'importanceIsManual': importanceIsManual,
      'visibility': visibility,
      'tel': tel,
      'mobile': mobile,
      'email': email,
      'address': address,
      'note': note,
    });
    return PersonDetail.fromJson(response.data as Map<String, dynamic>);
  }

  Future<OcrDraft> ocrDraft(File image) async {
    final formData = FormData.fromMap({
      'image': await MultipartFile.fromFile(image.path, filename: image.uri.pathSegments.last),
    });
    // 名刺読み取りはマルチモーダルLLM（ローカルOllama等）呼び出しのため、既定の10秒より長くかかる場合がある。
    final response = await _dio.post(
      '/api/persons/ocr-draft',
      data: formData,
      options: Options(sendTimeout: const Duration(seconds: 120), receiveTimeout: const Duration(seconds: 120)),
    );
    return OcrDraft.fromJson(response.data as Map<String, dynamic>);
  }

  Future<List<ContactItem>> listContacts(String personId) async {
    final response = await _dio.get('/api/persons/$personId/contacts');
    return (response.data as List).map((e) => ContactItem.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<ContactItem> updateContactNote({
    required String personId,
    required String contactId,
    String? note,
  }) async {
    final response = await _dio.put('/api/persons/$personId/contacts/$contactId', data: {'note': note});
    return ContactItem.fromJson(response.data as Map<String, dynamic>);
  }

  Future<ContactItem> addContact({
    required String personId,
    required String contactType,
    required DateTime occurredAt,
    String? place,
    String? note,
  }) async {
    final response = await _dio.post('/api/persons/$personId/contacts', data: {
      'contactType': contactType,
      'occurredAt': occurredAt.toIso8601String(),
      'place': place,
      'note': note,
    });
    return ContactItem.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> generateCard(String personId) async {
    await _dio.post('/api/persons/$personId/cards/generate');
  }

  // F-005/F-006 AIによる人脈グラフ提案・グラフ取得
  Future<List<RelationSuggestion>> suggestRelations(String personId) async {
    final response = await _dio.get('/api/persons/$personId/relations/suggest');
    return (response.data as List).map((e) => RelationSuggestion.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> confirmRelations({
    required String personId,
    required List<RelationSuggestion> selected,
  }) async {
    await _dio.post('/api/persons/$personId/relations', data: {
      'relations': selected
          .map((s) => {
                'relatedPersonId': s.relatedPersonId,
                'relationType': s.relationType,
                'strength': s.strength,
              })
          .toList(),
    });
  }

  // F-005/F-006 手動登録: AI提案を経由せず、人物と関係種別を指定して直接登録する
  Future<void> createRelation({
    required String personId,
    required String relatedPersonId,
    required String relationType,
    required int strength,
    bool isBidirectional = false,
  }) async {
    await _dio.post('/api/persons/$personId/relations', data: {
      'relations': [
        {
          'relatedPersonId': relatedPersonId,
          'relationType': relationType,
          'strength': strength,
          'isBidirectional': isBidirectional,
        },
      ],
    });
  }

  Future<NetworkGraph> getNetwork(String personId, {int maxDepth = 2}) async {
    final response = await _dio.get('/api/persons/$personId/network', queryParameters: {
      'maxDepth': maxDepth,
    });
    return NetworkGraph.fromJson(response.data as Map<String, dynamic>);
  }

  // F-005/F-006: 自分を中心とした人脈マインドマップ
  Future<NetworkGraph> getMyNetwork() async {
    final response = await _dio.get('/api/network');
    return NetworkGraph.fromJson(response.data as Map<String, dynamic>);
  }
}
