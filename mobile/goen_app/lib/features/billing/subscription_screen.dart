import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'billing_repository.dart';

const _standardPlanCode = 'standard_monthly';

String _statusLabel(String status) => switch (status) {
      'trialing' => 'トライアル中',
      'active' => '契約中',
      'past_due' => '支払いエラー',
      'canceled' => '未契約',
      _ => '未契約',
    };

Color _statusColor(BuildContext context, String status) => switch (status) {
      'active' || 'trialing' => Colors.green,
      'past_due' => Theme.of(context).colorScheme.error,
      _ => Colors.grey,
    };

/// プラン・お支払い画面。決済プロバイダはStripeを想定するが、Google Play/App Store配布時は
/// ストアのIAPへ切り替える可能性があるため、本画面はISubscriptionServiceの抽象（状態文字列・
/// チェックアウト/ポータルのURL発行）のみに依存し、Stripe固有の型には触れない。
class SubscriptionScreen extends ConsumerStatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  ConsumerState<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends ConsumerState<SubscriptionScreen> {
  bool _isProcessingCheckout = false;
  bool _isProcessingPortal = false;

  Future<void> _openUrlOrRefresh(String url, {required String mockSuccessMessage}) async {
    if (url.isEmpty) {
      // モック環境: ブラウザを開かず即座に状態を反映する
      ref.invalidate(subscriptionStatusProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mockSuccessMessage)));
      }
      return;
    }
    final uri = Uri.parse(url);
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ページを開けませんでした')));
      return;
    }
    // ブラウザでの手続き完了後、アプリに戻った際に最新状態を見せるため無効化しておく
    ref.invalidate(subscriptionStatusProvider);
  }

  Future<void> _startCheckout() async {
    setState(() => _isProcessingCheckout = true);
    try {
      final url = await ref.read(billingRepositoryProvider).createCheckoutSession(_standardPlanCode);
      await _openUrlOrRefresh(url, mockSuccessMessage: '契約が完了しました（開発環境のモック決済）');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('手続きを開始できませんでした: $e')));
      }
    } finally {
      if (mounted) setState(() => _isProcessingCheckout = false);
    }
  }

  Future<void> _openPortal() async {
    setState(() => _isProcessingPortal = true);
    try {
      final url = await ref.read(billingRepositoryProvider).createPortalSession();
      await _openUrlOrRefresh(url, mockSuccessMessage: '契約情報を更新しました（開発環境のモック決済）');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('お支払い管理ページを開けませんでした: $e')));
      }
    } finally {
      if (mounted) setState(() => _isProcessingPortal = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusAsync = ref.watch(subscriptionStatusProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('プラン・お支払い')),
      body: statusAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, st) => Center(child: Text('契約状態を取得できませんでした: $err')),
        data: (status) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.circle, size: 12, color: _statusColor(context, status.status)),
                        const SizedBox(width: 8),
                        Text(_statusLabel(status.status), style: Theme.of(context).textTheme.titleMedium),
                      ],
                    ),
                    if (status.planCode != null) ...[
                      const SizedBox(height: 8),
                      Text('プラン: ${status.planCode}'),
                    ],
                    if (status.currentPeriodEnd != null) ...[
                      const SizedBox(height: 4),
                      Text('次回更新日: ${DateFormat('yyyy/MM/dd').format(status.currentPeriodEnd!.toLocal())}'),
                    ],
                    if (status.trialEndsAt != null) ...[
                      const SizedBox(height: 4),
                      Text('トライアル終了日: ${DateFormat('yyyy/MM/dd').format(status.trialEndsAt!.toLocal())}'),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            if (!status.isActive) ...[
              Text('スタンダードプラン', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              const Text('人物カルテ登録数無制限、AI機能フル活用など、GOENのすべての機能を利用できます。'),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _isProcessingCheckout ? null : _startCheckout,
                child: _isProcessingCheckout
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('契約する'),
              ),
            ] else ...[
              OutlinedButton(
                onPressed: _isProcessingPortal ? null : _openPortal,
                child: _isProcessingPortal
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('お支払い方法・解約の管理'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
