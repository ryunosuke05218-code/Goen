import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';

final billingRepositoryProvider = Provider<BillingRepository>((ref) {
  return BillingRepository(ref.watch(apiClientProvider).dio);
});

// サブスク契約状態。取得APIを呼ぶたびに最新化するためautoDisposeのFutureProviderとする
// （Checkout/Portalから戻った後は明示的にinvalidateして再取得する）。
final subscriptionStatusProvider = FutureProvider.autoDispose<SubscriptionStatus>((ref) {
  return ref.watch(billingRepositoryProvider).getStatus();
});

class SubscriptionStatus {
  SubscriptionStatus({
    required this.status,
    required this.provider,
    required this.planCode,
    required this.currentPeriodEnd,
    required this.trialEndsAt,
  });

  factory SubscriptionStatus.fromJson(Map<String, dynamic> json) => SubscriptionStatus(
        status: json['status'] as String,
        provider: json['provider'] as String?,
        planCode: json['planCode'] as String?,
        currentPeriodEnd: json['currentPeriodEnd'] != null ? DateTime.parse(json['currentPeriodEnd'] as String) : null,
        trialEndsAt: json['trialEndsAt'] != null ? DateTime.parse(json['trialEndsAt'] as String) : null,
      );

  final String status; // trialing / active / past_due / canceled / incomplete
  final String? provider; // stripe / google_play / app_store
  final String? planCode;
  final DateTime? currentPeriodEnd;
  final DateTime? trialEndsAt;

  bool get isActive => status == 'active' || status == 'trialing';
}

class BillingRepository {
  BillingRepository(this._dio);
  final Dio _dio;

  Future<SubscriptionStatus> getStatus() async {
    final response = await _dio.get('/api/billing/subscription');
    return SubscriptionStatus.fromJson(response.data as Map<String, dynamic>);
  }

  // 戻り値のURLが空文字の場合はモック環境での即時契約完了を示す（呼び出し元はブラウザを開かず状態を再取得する）
  Future<String> createCheckoutSession(String planCode) async {
    final response = await _dio.post('/api/billing/checkout', data: {'planCode': planCode});
    return (response.data as Map<String, dynamic>)['url'] as String;
  }

  Future<String> createPortalSession() async {
    final response = await _dio.post('/api/billing/portal');
    return (response.data as Map<String, dynamic>)['url'] as String;
  }
}
