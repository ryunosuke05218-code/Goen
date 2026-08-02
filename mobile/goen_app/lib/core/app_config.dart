import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

/// 開発用のAPIベースURL。
/// Android実機/エミュレータからは 10.0.2.2 でホストPCのlocalhostへ到達できる。
/// iOSシミュレータ・Webはホストのlocalhostをそのまま利用できる。
/// 実機での動作確認やステージング接続時は --dart-define=API_BASE_URL=https://... で上書きする。
class AppConfig {
  static const _override = String.fromEnvironment('API_BASE_URL');

  static String get apiBaseUrl {
    if (_override.isNotEmpty) return _override;
    // ポート番号は backend/src/Goen.Api/Properties/launchSettings.json の "http" プロファイル(applicationUrl)に合わせる
    if (kIsWeb) return 'http://localhost:5295';
    if (!kIsWeb && Platform.isAndroid) return 'http://10.0.2.2:5295';
    return 'http://localhost:5295';
  }
}
