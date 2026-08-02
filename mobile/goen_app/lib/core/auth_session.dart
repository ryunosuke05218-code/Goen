import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_config.dart';
import 'token_storage.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthState {
  const AuthState({required this.status, this.userDisplayName, this.email});

  final AuthStatus status;
  final String? userDisplayName;
  final String? email;

  static const initial = AuthState(status: AuthStatus.unknown);
}

/// F-001 ログイン機能のセッション状態を管理する。
/// 2回目以降の起動ではリフレッシュトークンの有無のみで認証画面をスキップする（トークン検証はAPI呼び出し時に行う）。
class AuthSessionNotifier extends Notifier<AuthState> {
  late TokenStorage _storage;

  @override
  AuthState build() {
    _storage = ref.watch(tokenStorageProvider);
    _restoreSession();
    return AuthState.initial;
  }

  Future<void> _restoreSession() async {
    try {
      final refreshToken = await _storage.readRefreshToken();
      state = AuthState(status: refreshToken == null ? AuthStatus.unauthenticated : AuthStatus.authenticated);
    } catch (_) {
      // セキュアストレージが利用できない環境（一部のテスト実行環境等）では未認証として扱う
      state = const AuthState(status: AuthStatus.unauthenticated);
    }
  }

  Future<String?> login({required String email, required String password}) async {
    final dio = Dio(BaseOptions(baseUrl: AppConfig.apiBaseUrl));
    try {
      final response = await dio.post('/api/auth/login', data: {
        'email': email,
        'password': password,
      });
      final data = response.data as Map<String, dynamic>;
      await _storage.saveTokens(
        accessToken: data['accessToken'] as String,
        refreshToken: data['refreshToken'] as String,
      );
      final user = data['user'] as Map<String, dynamic>;
      state = AuthState(
        status: AuthStatus.authenticated,
        userDisplayName: user['displayName'] as String?,
        email: user['email'] as String?,
      );
      return null;
    } on DioException catch (e) {
      if (e.response?.statusCode == 423) {
        return 'ログイン試行回数が上限に達しました。しばらくしてから再度お試しください。';
      }
      if (e.response?.statusCode == 401) {
        return 'メールアドレスまたはパスワードが正しくありません。';
      }
      return '通信エラーが発生しました。接続先設定(API_BASE_URL)を確認してください。';
    }
  }

  Future<void> logout() async {
    await _storage.clear();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  void handleSessionExpired() {
    _storage.clear();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }
}
