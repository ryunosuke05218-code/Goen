import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_config.dart';
import 'biometric_settings.dart';
import 'token_storage.dart';

// F-001: lockedは「有効なリフレッシュトークンはあるが、生体認証が有効なためロック解除が必要」な状態。
enum AuthStatus { unknown, authenticated, unauthenticated, locked }

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
      if (refreshToken == null) {
        state = const AuthState(status: AuthStatus.unauthenticated);
        return;
      }
      // F-001: 生体認証が有効な場合は、ロック解除（unlockWithBiometrics）が成功するまでauthenticatedにしない
      bool biometricEnabled;
      try {
        final prefs = await SharedPreferences.getInstance();
        biometricEnabled = prefs.getBool(biometricEnabledPrefsKey) ?? false;
      } catch (_) {
        biometricEnabled = false;
      }
      state = AuthState(status: biometricEnabled ? AuthStatus.locked : AuthStatus.authenticated);
    } catch (_) {
      // セキュアストレージが利用できない環境（一部のテスト実行環境等）では未認証として扱う
      state = const AuthState(status: AuthStatus.unauthenticated);
    }
  }

  /// F-001: 生体認証（またはそのフォールバック）に成功した際にロックを解除する
  void unlockWithBiometrics() {
    if (state.status != AuthStatus.locked) return;
    state = AuthState(status: AuthStatus.authenticated, userDisplayName: state.userDisplayName, email: state.email);
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
