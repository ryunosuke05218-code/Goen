import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/biometric_settings.dart';
import '../../core/providers.dart';

/// F-001: 生体認証ログインが有効な場合、起動時にここでロック解除を求める。
/// 失敗・非対応時はパスワードでログインし直せる（要件定義書の例外・エラー処理どおり）。
class UnlockScreen extends ConsumerStatefulWidget {
  const UnlockScreen({super.key});

  @override
  ConsumerState<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends ConsumerState<UnlockScreen> {
  bool _isAuthenticating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // アプリ起動直後に自動で生体認証を要求する（銀行アプリ等と同様のUX）
    WidgetsBinding.instance.addPostFrameCallback((_) => _authenticate());
  }

  Future<void> _authenticate() async {
    setState(() {
      _isAuthenticating = true;
      _error = null;
    });
    final success = await ref.read(biometricSettingsProvider.notifier).authenticate();
    if (!mounted) return;
    if (success) {
      ref.read(authSessionProvider.notifier).unlockWithBiometrics();
    } else {
      setState(() => _error = '認証に失敗しました。もう一度お試しいただくか、パスワードでログインしてください。');
    }
    if (mounted) setState(() => _isAuthenticating = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.fingerprint, size: 72, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 16),
              const Text('GOEN', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('生体認証でロックを解除してください', textAlign: TextAlign.center),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error), textAlign: TextAlign.center),
              ],
              const SizedBox(height: 24),
              FilledButton.icon(
                icon: _isAuthenticating
                    ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.fingerprint),
                label: const Text('もう一度試す'),
                onPressed: _isAuthenticating ? null : _authenticate,
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => ref.read(authSessionProvider.notifier).handleSessionExpired(),
                child: const Text('パスワードでログインし直す'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
