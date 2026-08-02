import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';

/// S-015 設定画面。プロフィール・通知設定・公開範囲・ログアウトを扱う。
/// 本スキャフォールドではログアウトのみ実装する。
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authSessionProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('設定')),
      body: ListView(
        children: [
          if (auth.email != null)
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(auth.userDisplayName ?? ''),
              subtitle: Text(auth.email!),
            ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('ログアウト'),
            onTap: () => ref.read(authSessionProvider.notifier).logout(),
          ),
        ],
      ),
    );
  }
}
