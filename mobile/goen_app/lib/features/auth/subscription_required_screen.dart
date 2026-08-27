import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';

/// F-001拡張: 有効なサブスク契約がない（未契約・期限切れ）場合に表示する画面。
/// アプリ内には契約導線を置かない方針のため、契約自体はWebサイトで行ってもらい、
/// ここでは状況の説明と「更新を確認する」（再チェック）のみを提供する。
class SubscriptionRequiredScreen extends ConsumerStatefulWidget {
  const SubscriptionRequiredScreen({super.key});

  @override
  ConsumerState<SubscriptionRequiredScreen> createState() => _SubscriptionRequiredScreenState();
}

class _SubscriptionRequiredScreenState extends ConsumerState<SubscriptionRequiredScreen> {
  bool _isChecking = false;

  Future<void> _recheck() async {
    setState(() => _isChecking = true);
    final active = await ref.read(authSessionProvider.notifier).recheckSubscription();
    if (!mounted) return;
    setState(() => _isChecking = false);
    if (!active) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('まだご契約が確認できませんでした。しばらくしてから再度お試しください。')),
      );
    }
    // activeの場合はauthSessionProviderの状態変化がgo_routerのredirectを起動し、自動的に/homeへ遷移する
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock_clock_outlined, size: 64, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(height: 16),
                  Text(
                    'ご利用にはご契約が必要です',
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'サブスクリプションが未契約か、有効期限が切れています。'
                    'ご登録時にご利用いただいたGOEN公式Webサイトから、ご契約・お支払い方法のご確認をお願いいたします。',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  FilledButton(
                    onPressed: _isChecking ? null : _recheck,
                    child: _isChecking
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('更新を確認する'),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => ref.read(authSessionProvider.notifier).logout(),
                    child: const Text('ログアウト'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
