import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';

final introLetterRepositoryProvider = Provider<IntroLetterRepository>((ref) {
  return IntroLetterRepository(ref.watch(apiClientProvider).dio);
});

class IntroLetterRepository {
  IntroLetterRepository(this._dio);
  final Dio _dio;

  // F-026拡張: 任意でHPリンク・資料ファイル（画像/PDF/テキスト）を添付でき、AIがその内容も踏まえて文面を作成する
  Future<String> generate({
    required String targetPersonId,
    required String requirement,
    String? tone,
    String? lengthHint,
    String? additionalNotes,
    String? hpUrl,
    File? file,
  }) async {
    final formData = FormData.fromMap({
      'targetPersonId': targetPersonId,
      'requirement': requirement,
      if (tone != null) 'tone': tone,
      if (lengthHint != null) 'lengthHint': lengthHint,
      if (additionalNotes != null) 'additionalNotes': additionalNotes,
      if (hpUrl != null && hpUrl.isNotEmpty) 'hpUrl': hpUrl,
      if (file != null) 'file': await MultipartFile.fromFile(file.path, filename: file.uri.pathSegments.last),
    });
    // チャットLLM呼び出し（HPリンク取得・マルチモーダル添付を含む場合あり）を伴うため、長めのタイムアウトにする。
    final response = await _dio.post(
      '/api/intro-letters/generate',
      data: formData,
      options: Options(sendTimeout: const Duration(seconds: 120), receiveTimeout: const Duration(seconds: 120)),
    );
    return (response.data as Map<String, dynamic>)['message'] as String;
  }

  Future<List<IntroLetterHistoryItem>> getHistory() async {
    final response = await _dio.get('/api/intro-letters/history');
    return (response.data as List).map((e) => IntroLetterHistoryItem.fromJson(e as Map<String, dynamic>)).toList();
  }
}

// 過去の紹介文作成の依頼・生成結果履歴（1件）。人脈図画面から過去のやり取りを読み返すために使う。
class IntroLetterHistoryItem {
  IntroLetterHistoryItem({
    required this.requestId,
    required this.targetPersonId,
    required this.targetPersonName,
    required this.requirement,
    this.tone,
    this.lengthHint,
    this.additionalNotes,
    this.hpUrl,
    this.attachedFileName,
    required this.generatedMessage,
    required this.createdAt,
  });

  final String requestId;
  final String targetPersonId;
  final String targetPersonName;
  final String requirement;
  final String? tone;
  final String? lengthHint;
  final String? additionalNotes;
  final String? hpUrl;
  final String? attachedFileName;
  final String generatedMessage;
  final DateTime createdAt;

  factory IntroLetterHistoryItem.fromJson(Map<String, dynamic> json) => IntroLetterHistoryItem(
        requestId: json['requestId'] as String,
        targetPersonId: json['targetPersonId'] as String,
        targetPersonName: json['targetPersonName'] as String,
        requirement: json['requirement'] as String,
        tone: json['tone'] as String?,
        lengthHint: json['lengthHint'] as String?,
        additionalNotes: json['additionalNotes'] as String?,
        hpUrl: json['hpUrl'] as String?,
        attachedFileName: json['attachedFileName'] as String?,
        generatedMessage: json['generatedMessage'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
      );
}
