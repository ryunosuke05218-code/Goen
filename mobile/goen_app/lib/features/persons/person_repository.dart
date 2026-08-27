import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import 'models/person_models.dart';

final personRepositoryProvider = Provider<PersonRepository>((ref) {
  return PersonRepository(ref.watch(apiClientProvider).dio);
});

// 自分自身の人物カルテ（isSelf）。ダッシュボード・人物一覧の双方から参照する共有プロバイダ。
final selfPersonProvider = FutureProvider.autoDispose<PersonDetail?>((ref) {
  return ref.watch(personRepositoryProvider).getMe();
});

class PersonRepository {
  PersonRepository(this._dio);
  final Dio _dio;

  // F-003: sortでソート順を切り替えられる。総登録人数（totalCount）も併せて返る。
  Future<PersonListResponse> list({String? query, PersonSortOrder sort = PersonSortOrder.lastContact}) async {
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

  // 自分自身の人物カルテ（isSelf）。未登録の場合はnull。
  Future<PersonDetail?> getMe() async {
    final response = await _dio.get('/api/persons/me');
    final data = response.data;
    if (data is! Map<String, dynamic>) return null;
    return PersonDetail.fromJson(data);
  }

  Future<PersonDetail> create({
    required String fullName,
    String? fullNameKana,
    String? department,
    String? jobTitle,
    String? occupationName,
    String? industryName,
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
    bool isSelf = false,
  }) async {
    final response = await _dio.post('/api/persons', data: {
      'fullName': fullName,
      'fullNameKana': fullNameKana,
      'department': department,
      'jobTitle': jobTitle,
      'occupationName': occupationName,
      'industryName': industryName,
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
      'isSelf': isSelf,
    });
    return PersonDetail.fromJson(response.data as Map<String, dynamic>);
  }

  Future<PersonDetail> update({
    required String personId,
    required String fullName,
    String? fullNameKana,
    String? department,
    String? jobTitle,
    String? occupationName,
    String? industryName,
    String? companyName,
    required String visibility,
    String? tel,
    String? mobile,
    String? email,
    String? address,
    String? note,
    String? metPlace,
    List<SnsLink> snsLinks = const [],
    String? introducerPersonId,
  }) async {
    final response = await _dio.put('/api/persons/$personId', data: {
      'fullName': fullName,
      'fullNameKana': fullNameKana,
      'department': department,
      'jobTitle': jobTitle,
      'occupationName': occupationName,
      'industryName': industryName,
      'companyName': companyName,
      'visibility': visibility,
      'tel': tel,
      'mobile': mobile,
      'email': email,
      'address': address,
      'note': note,
      'metPlace': metPlace,
      'snsLinks': snsLinks.map((s) => s.toJson()).toList(),
      'introducerPersonId': introducerPersonId,
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
      // サーバー側はDateTimeOffsetをUTC(Offset=0)としてしか受け付けない（Npgsqlのtimestamptz制約）ため、
      // ローカル時刻のまま送るとタイムゾーン付きの文字列になり書き込み時に例外になる。必ずUTCに変換して送る。
      'occurredAt': occurredAt.toUtc().toIso8601String(),
      'place': place,
      'note': note,
    });
    return ContactItem.fromJson(response.data as Map<String, dynamic>);
  }

  // F-011拡張: 接点メモをAIが要約する。押すたびに最新のメモ内容で作り直し、DBへ上書き保存する
  Future<ContactItem> summarizeContactNote({required String personId, required String contactId}) async {
    final response = await _dio.post(
      '/api/persons/$personId/contacts/$contactId/summarize',
      options: Options(sendTimeout: const Duration(seconds: 60), receiveTimeout: const Duration(seconds: 60)),
    );
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

  // F-038 AI自動リサーチ: 既存の生成結果を取得する（未生成の場合はnull）
  Future<PersonResearch?> getResearch(String personId) async {
    final response = await _dio.get('/api/persons/$personId/research');
    final data = response.data;
    if (data is! Map<String, dynamic>) return null;
    return PersonResearch.fromJson(data);
  }

  // F-038: 氏名・会社名をもとにAIがWeb検索し、参考情報を生成する（既存があれば上書き）
  Future<PersonResearch> generateResearch(String personId) async {
    // Web検索＋ローカルLLM呼び出しを伴うため長めのタイムアウトとする
    final response = await _dio.post(
      '/api/persons/$personId/research/generate',
      options: Options(sendTimeout: const Duration(seconds: 120), receiveTimeout: const Duration(seconds: 120)),
    );
    return PersonResearch.fromJson(response.data as Map<String, dynamic>);
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
