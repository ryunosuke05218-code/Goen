import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// テスト等でDI差し替えできるよう抽象化する。
final tokenStorageProvider = Provider<TokenStorage>((ref) => SecureTokenStorage());

/// F-001: アクセストークン／リフレッシュトークンを端末に安全に保存する。
abstract class TokenStorage {
  Future<void> saveTokens({required String accessToken, required String refreshToken});
  Future<String?> readAccessToken();
  Future<String?> readRefreshToken();
  Future<void> clear();
}

class SecureTokenStorage implements TokenStorage {
  final _storage = const FlutterSecureStorage();

  static const _accessTokenKey = 'goen.access_token';
  static const _refreshTokenKey = 'goen.refresh_token';

  @override
  Future<void> saveTokens({required String accessToken, required String refreshToken}) async {
    await _storage.write(key: _accessTokenKey, value: accessToken);
    await _storage.write(key: _refreshTokenKey, value: refreshToken);
  }

  @override
  Future<String?> readAccessToken() => _storage.read(key: _accessTokenKey);

  @override
  Future<String?> readRefreshToken() => _storage.read(key: _refreshTokenKey);

  @override
  Future<void> clear() async {
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _refreshTokenKey);
  }
}
