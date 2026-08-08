import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 設定画面（S-015）の文字の大きさ選択肢。factorはMediaQueryのTextScalerへ渡す倍率。
enum AppTextScale {
  small(0.85, '小'),
  normal(1.0, '標準'),
  large(1.15, '大'),
  extraLarge(1.3, '特大');

  const AppTextScale(this.factor, this.label);
  final double factor;
  final String label;
}

class DisplaySettings {
  const DisplaySettings({this.themeMode = ThemeMode.system, this.textScale = AppTextScale.normal});

  final ThemeMode themeMode;
  final AppTextScale textScale;

  DisplaySettings copyWith({ThemeMode? themeMode, AppTextScale? textScale}) {
    return DisplaySettings(
      themeMode: themeMode ?? this.themeMode,
      textScale: textScale ?? this.textScale,
    );
  }
}

const _themeModeKey = 'display_theme_mode';
const _textScaleKey = 'display_text_scale';

/// 画面設定（ダークモード・文字の大きさ）を保持し、端末に永続化する。
/// 起動時はデフォルト値を即座に返し、SharedPreferencesからの復元は非同期で反映する
/// （AuthSessionNotifierのセッション復元と同じパターン）。
class DisplaySettingsNotifier extends Notifier<DisplaySettings> {
  @override
  DisplaySettings build() {
    _restore();
    return const DisplaySettings();
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final themeModeName = prefs.getString(_themeModeKey);
      final textScaleName = prefs.getString(_textScaleKey);

      state = DisplaySettings(
        themeMode: ThemeMode.values.firstWhere(
          (mode) => mode.name == themeModeName,
          orElse: () => ThemeMode.system,
        ),
        textScale: AppTextScale.values.firstWhere(
          (scale) => scale.name == textScaleName,
          orElse: () => AppTextScale.normal,
        ),
      );
    } catch (_) {
      // 端末側でSharedPreferencesが利用できない環境ではデフォルト値のまま扱う
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeModeKey, mode.name);
  }

  Future<void> setTextScale(AppTextScale scale) async {
    state = state.copyWith(textScale: scale);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_textScaleKey, scale.name);
  }
}

final displaySettingsProvider = NotifierProvider<DisplaySettingsNotifier, DisplaySettings>(
  DisplaySettingsNotifier.new,
);
