import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import 'models/assistant_models.dart';

final aiAssistantRepositoryProvider = Provider<AiAssistantRepository>((ref) {
  return AiAssistantRepository(ref.watch(apiClientProvider).dio);
});

class AiAssistantRepository {
  AiAssistantRepository(this._dio);
  final Dio _dio;

  Future<AssistantResult> query(String instruction) async {
    // ローカルLLM(Ollama等)は1回の質問で埋め込み生成+LLM呼び出しを複数回行うため、
    // クラウドAPIより応答に時間がかかることがある。このエンドポイントだけ長めのタイムアウトにする。
    final response = await _dio.post(
      '/api/ai-assistant/query',
      data: {'instruction': instruction},
      options: Options(
        sendTimeout: const Duration(seconds: 120),
        receiveTimeout: const Duration(seconds: 120),
      ),
    );
    return AssistantResult.fromJson(response.data as Map<String, dynamic>);
  }
}
