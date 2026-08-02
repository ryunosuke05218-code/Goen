import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';

final introLetterRepositoryProvider = Provider<IntroLetterRepository>((ref) {
  return IntroLetterRepository(ref.watch(apiClientProvider).dio);
});

class IntroLetterRepository {
  IntroLetterRepository(this._dio);
  final Dio _dio;

  Future<String> generate({
    required String targetPersonId,
    required String requirement,
    String? tone,
    String? lengthHint,
    String? additionalNotes,
  }) async {
    // チャットLLM呼び出しを伴うため、ローカルAI(Ollama等)想定で長めのタイムアウトにする。
    final response = await _dio.post(
      '/api/intro-letters/generate',
      data: {
        'targetPersonId': targetPersonId,
        'requirement': requirement,
        'tone': tone,
        'lengthHint': lengthHint,
        'additionalNotes': additionalNotes,
      },
      options: Options(sendTimeout: const Duration(seconds: 120), receiveTimeout: const Duration(seconds: 120)),
    );
    return (response.data as Map<String, dynamic>)['message'] as String;
  }
}
