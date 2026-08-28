import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_config.dart';
import 'biometric_settings.dart';
import 'token_storage.dart';

// F-001: lockedは「有効なリフレッシュトークンはあるが、生体認証が有効なためロック解除が必要」な状態。
// subscriptionRequiredは「ログインはできたが、有効なサブスク契約がない（未契約・期限切れ）」状態。
// アプリ内には契約導線を置かない方針のため、この状態ではWebサイトでの契約を促す専用画面に留める。
enum AuthStatus { unknown, authenticated, unauthenticated, locked, subscriptionRequired }

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
      final accessToken = data['accessToken'] as String;
      await _storage.saveTokens(
        accessToken: accessToken,
        refreshToken: data['refreshToken'] as String,
      );
      final user = data['user'] as Map<String, dynamic>;
      final displayName = user['displayName'] as String?;
      final userEmail = user['email'] as String?;

      // ログイン直後に契約状況を確認し、未契約・期限切れの場合はそのまま案内画面へ振り分ける
      // （アプリ内に契約導線がないため、これがユーザーへ状況を伝える最初の機会になる）。
      final subscriptionActive = await _checkSubscriptionActive(accessToken);
      state = AuthState(
        status: subscriptionActive ? AuthStatus.authenticated : AuthStatus.subscriptionRequired,
        userDisplayName: displayName,
        email: userEmail,
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

  // サブスク課金ゲート: /api/billing/subscription はゲート対象外（AllowInactiveSubscription）のため、
  // 未契約・期限切れの状態でも必ず結果を返す。
  Future<bool> _checkSubscriptionActive(String accessToken) async {
    final dio = Dio(BaseOptions(baseUrl: AppConfig.apiBaseUrl));
    try {
      final response = await dio.get(
        '/api/billing/subscription',
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      final status = (response.data as Map<String, dynamic>)['status'] as String?;
      return status == 'active' || status == 'trialing';
    } on DioException {
      // 通信エラー時は判定できないため、利用不可にはせず現状維持側（true）に倒す
      // （バックエンド側のSubscriptionGateFilterが実際のAPI呼び出し時にあらためて正しく判定する）。
      return true;
    }
  }

  /// subscriptionRequired画面の「更新を確認する」ボタンから呼ばれる。
  /// 有効な契約が確認できればauthenticatedへ復帰させる（成功時はgo_routerが自動的に/homeへ遷移する）。
  Future<bool> recheckSubscription() async {
    final accessToken = await _storage.readAccessToken();
    if (accessToken == null) return false;
    final active = await _checkSubscriptionActive(accessToken);
    if (active) {
      state = AuthState(status: AuthStatus.authenticated, userDisplayName: state.userDisplayName, email: state.email);
    }
    return active;
  }

  /// APIクライアントが402（サブスク未契約・期限切れ）を検知した際に呼ばれる。
  void handleSubscriptionRequired() {
    if (state.status != AuthStatus.authenticated) return;
    state = AuthState(status: AuthStatus.subscriptionRequired, userDisplayName: state.userDisplayName, email: state.email);
  }

  // 設定画面: メールアドレス変更。本人確認のため現在のパスワードが必要。
  Future<String?> changeEmail({required String newEmail, required String currentPassword}) async {
    final accessToken = await _storage.readAccessToken();
    if (accessToken == null) return 'ログインし直してから再度お試しください。';

    final dio = Dio(BaseOptions(baseUrl: AppConfig.apiBaseUrl));
    try {
      await dio.put(
        '/api/auth/email',
        data: {'newEmail': newEmail, 'currentPassword': currentPassword},
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      state = AuthState(status: state.status, userDisplayName: state.userDisplayName, email: newEmail);
      return null;
    } on DioException catch (e) {
      final message = (e.response?.data is Map) ? (e.response?.data as Map)['message'] as String? : null;
      if (e.response?.statusCode == 401) {
        return message ?? '現在のパスワードが正しくありません。';
      }
      if (e.response?.statusCode == 409) {
        return message ?? 'このメールアドレスは既に使用されています。';
      }
      return message ?? '通信エラーが発生しました。接続先設定(API_BASE_URL)を確認してください。';
    }
  }

  // 設定画面: パスワード変更（ログイン中に実施）。成功時は新しいトークンをそのまま保存し、再ログイン不要にする。
  Future<String?> changePassword({required String currentPassword, required String newPassword}) async {
    final accessToken = await _storage.readAccessToken();
    if (accessToken == null) return 'ログインし直してから再度お試しください。';

    final dio = Dio(BaseOptions(baseUrl: AppConfig.apiBaseUrl));
    try {
      final response = await dio.put(
        '/api/auth/password',
        data: {'currentPassword': currentPassword, 'newPassword': newPassword},
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      final data = response.data as Map<String, dynamic>;
      await _storage.saveTokens(
        accessToken: data['accessToken'] as String,
        refreshToken: data['refreshToken'] as String,
      );
      return null;
    } on DioException catch (e) {
      final message = (e.response?.data is Map) ? (e.response?.data as Map)['message'] as String? : null;
      if (e.response?.statusCode == 401) {
        return message ?? '現在のパスワードが正しくありません。';
      }
      if (e.response?.statusCode == 400) {
        return message ?? '入力内容を確認してください。';
      }
      return message ?? '通信エラーが発生しました。接続先設定(API_BASE_URL)を確認してください。';
    }
  }

  // バックエンドはメールアドレスの存在有無に関わらず常に200を返す（列挙防止）。
  // 通信エラー時のみ success=false とし、呼び出し元は「コード入力へ進めてよいか」を判断できる。
  Future<(bool success, String message)> forgotPassword({required String email}) async {
    final dio = Dio(BaseOptions(baseUrl: AppConfig.apiBaseUrl));
    try {
      final response = await dio.post('/api/auth/forgot-password', data: {'email': email});
      final data = response.data as Map<String, dynamic>;
      return (true, data['message'] as String? ?? '再設定用のコードを送信しました。');
    } on DioException {
      return (false, '通信エラーが発生しました。接続先設定(API_BASE_URL)を確認してください。');
    }
  }

  Future<(bool success, String message)> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    final dio = Dio(BaseOptions(baseUrl: AppConfig.apiBaseUrl));
    try {
      final response = await dio.post('/api/auth/reset-password', data: {
        'email': email,
        'code': code,
        'newPassword': newPassword,
      });
      final data = response.data as Map<String, dynamic>;
      return (true, data['message'] as String? ?? 'パスワードを再設定しました。');
    } on DioException catch (e) {
      final message = (e.response?.data is Map) ? (e.response?.data as Map)['message'] as String? : null;
      return (false, message ?? '通信エラーが発生しました。接続先設定(API_BASE_URL)を確認してください。');
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
