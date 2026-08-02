import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:goen_app/app.dart';
import 'package:goen_app/core/token_storage.dart';

/// テスト環境ではプラットフォームチャンネルを要するセキュアストレージへ実アクセスできないため、
/// インメモリの偽実装に差し替える。
class FakeTokenStorage implements TokenStorage {
  String? _accessToken;
  String? _refreshToken;

  @override
  Future<void> saveTokens({required String accessToken, required String refreshToken}) async {
    _accessToken = accessToken;
    _refreshToken = refreshToken;
  }

  @override
  Future<String?> readAccessToken() async => _accessToken;

  @override
  Future<String?> readRefreshToken() async => _refreshToken;

  @override
  Future<void> clear() async {
    _accessToken = null;
    _refreshToken = null;
  }
}

void main() {
  testWidgets('未ログイン時はログイン画面が表示される', (WidgetTester tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [tokenStorageProvider.overrideWithValue(FakeTokenStorage())],
      child: const GoenApp(),
    ));
    // 起動直後はスプラッシュ→セッション復元（未認証）→ログイン画面へリダイレクトされる。
    // スプラッシュのCircularProgressIndicatorは無限アニメーションのためpumpAndSettleは使えない。
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('ログイン'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'メールアドレス'), findsOneWidget);
  });
}
