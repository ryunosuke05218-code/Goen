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

  // F-003: sortでソート順を切り替えられる。総登録人数（totalCount）も併せて返る。
  Future<PersonListResponse> list({String? query, PersonSortOrder sort = PersonSortOrder.importance}) async {
    final response = await _dio.get('/api/persons', queryParameters: {
      if (query != null && query.isNotEmpty) 'q': query,
      if (sort.queryValue.isNotEmpty) 'sort': sort.queryValue,
    });
    return PersonListResponse.fromJson(response.data as Map<String, dynamic>);
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
    String? occupationCode,
    String? companyName,
    String? tel,
    String? mobile,
    String? email,
    String? address,
    String? note,
    String? metPlace,
    List<SnsLink> snsLinks = const [],
    String sourceType = 'manual',
    String? introducerPersonId,
  }) async {
    final response = await _dio.post('/api/persons', data: {
      'fullName': fullName,
      'fullNameKana': fullNameKana,
      'department': department,
      'jobTitle': jobTitle,
      'occupationCode': occupationCode,
      'companyName': companyName,
      'tel': tel,
      'mobile': mobile,
      'email': email,
      'address': address,
      'note': note,
      'metPlace': metPlace,
      'snsLinks': snsLinks.map((s) => s.toJson()).toList(),
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
    String? occupationCode,
    String? companyName,
    required int importance,
    required bool importanceIsManual,
    required String visibility,
    String? tel,
    String? mobile,
    String? email,
    String? address,
    String? note,
    String? metPlace,
    List<SnsLink> snsLinks = const [],
  }) async {
    final response = await _dio.put('/api/persons/$personId', data: {
      'fullName': fullName,
      'fullNameKana': fullNameKana,
      'department': department,
      'jobTitle': jobTitle,
      'occupationCode': occupationCode,
      'companyName': companyName,
      'importance': importance,
      'importanceIsManual': importanceIsManual,
      'visibility': visibility,
      'tel': tel,
      'mobile': mobile,
      'email': email,
      'address': address,
      'note': note,
      'metPlace': metPlace,
      'snsLinks': snsLinks.map((s) => s.toJson()).toList(),
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

  // F-007: 登録内容確認画面の音声文字起こしを、フォームの現在値（OCR結果）と統合する
  Future<OcrDraft> refineOcrDraft({
    String? fullName,
    String? fullNameKana,
    String? companyName,
    String? department,
    String? jobTitle,
    String? tel,
    String? mobile,
    String? email,
    String? address,
    required String voiceText,
  }) async {
    final response = await _dio.post(
      '/api/persons/ocr-draft/refine',
      data: {
        'fullName': fullName,
        'fullNameKana': fullNameKana,
        'companyName': companyName,
        'department': department,
        'jobTitle': jobTitle,
        'tel': tel,
        'mobile': mobile,
        'email': email,
        'address': address,
        'voiceText': voiceText,
      },
      options: Options(sendTimeout: const Duration(seconds: 120), receiveTimeout: const Duration(seconds: 120)),
    );
    return OcrDraft.fromJson(response.data as Map<String, dynamic>);
  }

  // F-002: 手入力登録画面で、話した内容だけから各登録項目・メモをAIに振り分けてもらう
  Future<PersonVoiceDraft> voiceDraft(String voiceText) async {
    final response = await _dio.post(
      '/api/persons/voice-draft',
      data: {'voiceText': voiceText},
      options: Options(sendTimeout: const Duration(seconds: 120), receiveTimeout: const Duration(seconds: 120)),
    );
    return PersonVoiceDraft.fromJson(response.data as Map<String, dynamic>);
  }

  // 職種マスタ（Q-011解消）。人物編集・登録画面の選択肢、人脈図の凡例に使用
  Future<List<OccupationTypeItem>> listOccupationTypes() async {
    final response = await _dio.get('/api/masters/occupation-types');
    return (response.data as List).map((e) => OccupationTypeItem.fromJson(e as Map<String, dynamic>)).toList();
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

  // F-010: 任意でHPリンク・資料ファイルを渡し、これらも根拠に含めてAI要約を更新する
  Future<void> generateCard(String personId, {String? hpUrl, File? file}) async {
    final formData = FormData.fromMap({
      if (hpUrl != null && hpUrl.isNotEmpty) 'hpUrl': hpUrl,
      if (file != null) 'file': await MultipartFile.fromFile(file.path, filename: file.uri.pathSegments.last),
    });
    // HPリンク取得・ローカルLLMへのマルチモーダル入力は時間がかかる場合があるため長めのタイムアウトとする
    await _dio.post(
      '/api/persons/$personId/cards/generate',
      data: formData,
      options: Options(sendTimeout: const Duration(seconds: 120), receiveTimeout: const Duration(seconds: 120)),
    );
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

  // F-027: 同一組織の他ユーザー一覧（人脈図の閲覧対象選択に使用）
  Future<List<OrgMember>> listOrgMembers() async {
    final response = await _dio.get('/api/users');
    return (response.data as List).map((e) => OrgMember.fromJson(e as Map<String, dynamic>)).toList();
  }

  // F-027: 他ユーザーの人脈図を業種階層まで（人数集計のみ）で取得する
  Future<IndustryBreakdown> getIndustrySummary(String userId) async {
    final response = await _dio.get('/api/network/industry-summary', queryParameters: {'userId': userId});
    return IndustryBreakdown.fromJson(response.data as Map<String, dynamic>);
  }

  // F-028: 自分自身の設定（相互人脈登録のON/OFF等）
  Future<UserSettings> getMySettings() async {
    final response = await _dio.get('/api/users/me');
    return UserSettings.fromJson(response.data as Map<String, dynamic>);
  }

  Future<UserSettings> updateMySettings({required bool allowMutualRegistration}) async {
    final response = await _dio.put('/api/users/me/settings', data: {
      'allowMutualRegistration': allowMutualRegistration,
    });
    return UserSettings.fromJson(response.data as Map<String, dynamic>);
  }
}
