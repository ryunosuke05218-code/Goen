/// APIベースURL。
/// デフォルトは本番API（https://api.goen-app.com）。リリースビルドで
/// --dart-define を付け忘れても本番に繋がるようにするための安全側デフォルト。
/// ローカル開発時は --dart-define=API_BASE_URL=http://192.168.1.2:5295 のように
/// 開発機のIP（ポート番号は backend/src/Goen.Api/Properties/launchSettings.json の
/// "http" プロファイル(applicationUrl)に合わせる）で上書きする。
class AppConfig {
  static const _override = String.fromEnvironment('API_BASE_URL');

  static String get apiBaseUrl {
    if (_override.isNotEmpty) return _override;
    return 'https://api.goen-app.com';
  }
}
