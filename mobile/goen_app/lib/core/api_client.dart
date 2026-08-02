import 'package:dio/dio.dart';

import 'app_config.dart';
import 'token_storage.dart';

/// バックエンド(Goen.Api)への通信を担うクライアント。
/// アクセストークンの自動付与と、401発生時のリフレッシュ→再試行を行う（F-001）。
class ApiClient {
  ApiClient({required this.storage, required this.onSessionExpired}) {
    dio = Dio(BaseOptions(
      baseUrl: AppConfig.apiBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ));

    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await storage.readAccessToken();
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (error, handler) async {
        final isUnauthorized = error.response?.statusCode == 401;
        final isRefreshCall = error.requestOptions.path.contains('/api/auth/refresh');

        if (isUnauthorized && !isRefreshCall) {
          final refreshed = await _tryRefresh();
          if (refreshed) {
            try {
              final response = await dio.fetch(error.requestOptions);
              handler.resolve(response);
              return;
            } catch (_) {
              // 再試行も失敗した場合は下のセッション切れ処理へフォールスルーする
            }
          }
          await storage.clear();
          onSessionExpired();
        }
        handler.next(error);
      },
    ));
  }

  late final Dio dio;
  final TokenStorage storage;
  final void Function() onSessionExpired;

  Future<bool> _tryRefresh() async {
    final refreshToken = await storage.readRefreshToken();
    if (refreshToken == null) return false;

    try {
      // interceptorの無限ループを避けるため、専用のDioインスタンスで直接呼び出す
      final refreshDio = Dio(BaseOptions(baseUrl: AppConfig.apiBaseUrl));
      final response = await refreshDio.post('/api/auth/refresh', data: {
        'refreshToken': refreshToken,
      });
      await storage.saveTokens(
        accessToken: response.data['accessToken'] as String,
        refreshToken: response.data['refreshToken'] as String,
      );
      return true;
    } catch (_) {
      return false;
    }
  }
}
