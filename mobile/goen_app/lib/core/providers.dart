import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'auth_session.dart';
import 'token_storage.dart';

final authSessionProvider = NotifierProvider<AuthSessionNotifier, AuthState>(AuthSessionNotifier.new);

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(
    storage: ref.watch(tokenStorageProvider),
    onSessionExpired: () => ref.read(authSessionProvider.notifier).handleSessionExpired(),
  );
});
