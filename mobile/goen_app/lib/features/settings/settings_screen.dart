import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/biometric_settings.dart';
import '../../core/display_settings.dart';
import '../../core/providers.dart';
import '../home/main_bottom_nav_bar.dart';
import '../persons/person_repository.dart';

// GOEN公式Webサイト（会員登録・契約管理・法的情報のページ）。デプロイ先が変わった場合はここを更新する。
const _websiteBaseUrl = 'https://goen-app.com';

Future<void> _openLink(BuildContext context, String url) async {
  final uri = Uri.tryParse(url);
  final launched = uri != null && await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!launched && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('リンクを開けませんでした: $url')));
  }
}

Future<void> _showAccountDeletionInfo(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('アカウント削除について'),
      content: const Text(
        'アカウントの削除（退会）をご希望の場合は、GOEN公式Webサイトのサポート窓口までご連絡ください。\n\n'
        'ご契約中の場合は、削除の前にご登録時のWebサイトから解約手続きを行ってください。',
      ),
      actions: [
        FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('閉じる')),
      ],
    ),
  );
}

final userSettingsProvider = FutureProvider.autoDispose((ref) async {
  final repo = ref.watch(personRepositoryProvider);
  return repo.getMySettings();
});

/// S-015 設定画面。プロフィール・公開範囲・生体認証・相互人脈登録・ログアウトを扱う。
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key, this.returnPath});

  // 戻るボタンで明示的に戻したい遷移元（例: ダッシュボードの'/home?tab=0'）。未指定時は通常のpop()に任せる。
  final String? returnPath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authSessionProvider);
    final display = ref.watch(displaySettingsProvider);
    final displayNotifier = ref.read(displaySettingsProvider.notifier);
    final biometricEnabled = ref.watch(biometricSettingsProvider);
    final biometricSupportedAsync = ref.watch(biometricSupportedProvider);
    final userSettingsAsync = ref.watch(userSettingsProvider);

    return Scaffold(
      appBar: AppBar(
        leading: returnPath == null
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: '戻る',
                onPressed: () => context.go(returnPath!),
              ),
        title: const Text('設定'),
      ),
      body: ListView(
        children: [
          if (auth.email != null)
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(auth.userDisplayName ?? ''),
              subtitle: Text(auth.email!),
            ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('画面設定', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('文字の大きさ'),
                const SizedBox(height: 8),
                // 文字サイズを「特大」等に設定した状態でこの画面自体を開くと、4択分のラベルが画面幅に
                // 収まらずSegmentedButtonが各セグメントを強制的に圧縮し、日本語ラベルが1文字ずつ
                // 縦に折り返される不具合があった。横スクロール可能にして圧縮させないようにする。
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SegmentedButton<AppTextScale>(
                    segments: AppTextScale.values
                        .map((scale) => ButtonSegment(value: scale, label: Text(scale.label)))
                        .toList(),
                    selected: {display.textScale},
                    onSelectionChanged: (selection) => displayNotifier.setTextScale(selection.first),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('テーマ'),
                const SizedBox(height: 8),
                SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(
                      value: ThemeMode.system,
                      label: Text('自動'),
                      icon: Icon(Icons.brightness_auto),
                    ),
                    ButtonSegment(
                      value: ThemeMode.light,
                      label: Text('ライト'),
                      icon: Icon(Icons.light_mode),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      label: Text('ダーク'),
                      icon: Icon(Icons.dark_mode),
                    ),
                  ],
                  selected: {display.themeMode},
                  onSelectionChanged: (selection) => displayNotifier.setThemeMode(selection.first),
                ),
              ],
            ),
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('セキュリティ', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          biometricSupportedAsync.when(
            loading: () => const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()),
            error: (err, st) => const SizedBox.shrink(),
            data: (supported) {
              if (!supported) {
                return const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    'この端末では生体認証が利用できません（開発環境等ではメールアドレス・パスワードでログインしてください）',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                );
              }
              return SwitchListTile(
                title: const Text('指紋・顔認証でログイン'),
                subtitle: const Text('次回起動時、パスワードの代わりに生体認証でロックを解除します'),
                value: biometricEnabled,
                onChanged: (v) async {
                  if (v) {
                    final success = await ref.read(biometricSettingsProvider.notifier).authenticate();
                    if (!success) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(const SnackBar(content: Text('生体認証を確認できなかったため、有効化しませんでした')));
                      }
                      return;
                    }
                  }
                  await ref.read(biometricSettingsProvider.notifier).setEnabled(v);
                },
              );
            },
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('人脈連携', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          userSettingsAsync.when(
            loading: () => const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()),
            error: (err, st) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text('設定の取得に失敗しました: $err', style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ),
            data: (settings) => SwitchListTile(
              title: const Text('相互人脈登録'),
              subtitle: const Text('名刺登録した相手がGOENユーザーの場合、相手の人脈にも自分を自動登録することを許可します'),
              value: settings.allowMutualRegistration,
              onChanged: (v) async {
                try {
                  await ref.read(personRepositoryProvider).updateMySettings(allowMutualRegistration: v);
                  ref.invalidate(userSettingsProvider);
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('更新に失敗しました: $e')));
                  }
                }
              },
            ),
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('プラン', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              'ご契約・お支払い方法の変更・解約は、ご登録時にご利用いただいたGOEN公式Webサイトから行えます。',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('マスタ管理', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          ListTile(
            leading: const Icon(Icons.category_outlined),
            title: const Text('業種・職種の管理'),
            subtitle: const Text('人脈図（人脈マップ）の業種＞職種グルーピングに使う項目を編集・追加できます'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/masters/manage'),
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('法的情報', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('プライバシーポリシー'),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => _openLink(context, '$_websiteBaseUrl/privacy.html'),
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('利用規約'),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => _openLink(context, '$_websiteBaseUrl/terms.html'),
          ),
          ListTile(
            leading: const Icon(Icons.person_remove_outlined),
            title: const Text('アカウント削除について'),
            onTap: () => _showAccountDeletionInfo(context),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('ログアウト'),
            onTap: () => ref.read(authSessionProvider.notifier).logout(),
          ),
        ],
      ),
      bottomNavigationBar: const MainBottomNavBar(selectedIndex: 0),
    );
  }
}
