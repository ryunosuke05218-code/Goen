package com.goen.goen_app

import io.flutter.embedding.android.FlutterFragmentActivity

// local_auth（F-001 生体認証）はAndroidネイティブ側でandroidx.biometric.BiometricPromptを使うため、
// ホストActivityがFragmentActivityである必要がある。既定のFlutterActivityのままだと
// 生体認証が有効な端末でもcanCheckBiometrics/authenticate()が正しく動作しない。
class MainActivity : FlutterFragmentActivity()
