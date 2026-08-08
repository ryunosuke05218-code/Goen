import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// F-001: 生体認証ログインのON/OFF設定を保持するSharedPreferencesキー。
/// auth_session.dart側でも起動直後の判定に使うため公開定数にしている。
const biometricEnabledPrefsKey = 'biometric_login_enabled';

/// 生体認証（Face ID／指紋認証）のON/OFF設定と、端末OSへの認証リクエストを扱う。
/// 生体情報自体はアプリ・サーバーいずれにも送受信しない（端末OSの認証結果のみを受け取る）。
class BiometricSettingsNotifier extends Notifier<bool> {
  final LocalAuthentication _auth = LocalAuthentication();

  @override
  bool build() {
    _restore();
    return false;
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = prefs.getBool(biometricEnabledPrefsKey) ?? false;
    } catch (_) {
      // SharedPreferencesが利用できない環境では既定値（OFF）のまま扱う
    }
  }

  Future<void> setEnabled(bool enabled) async {
    state = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(biometricEnabledPrefsKey, enabled);
  }

  /// 対応端末かどうか（開発環境・非対応デバイスではfalseになる。F-001「開発環境はメール・パスワードのみ」に対応）
  Future<bool> isDeviceSupported() async {
    try {
      final supported = await _auth.isDeviceSupported();
      final canCheck = await _auth.canCheckBiometrics;
      return supported && canCheck;
    } catch (_) {
      return false;
    }
  }

  /// 端末OSの生体認証（またはPIN等のフォールバック）を要求する。成功可否のみを返す。
  Future<bool> authenticate() async {
    try {
      return await _auth.authenticate(
        localizedReason: 'GOENアプリのロックを解除します',
        options: const AuthenticationOptions(stickyAuth: true),
      );
    } catch (_) {
      return false;
    }
  }
}

final biometricSettingsProvider = NotifierProvider<BiometricSettingsNotifier, bool>(BiometricSettingsNotifier.new);

/// 設定画面での表示要否の判定に使う（端末が非対応ならトグル自体を隠す）
final biometricSupportedProvider = FutureProvider<bool>((ref) {
  return ref.watch(biometricSettingsProvider.notifier).isDeviceSupported();
});
