import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/biometric_settings.dart';
import '../../core/display_settings.dart';
import '../../core/providers.dart';
import '../home/main_bottom_nav_bar.dart';
import '../persons/models/person_models.dart';
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

// アカウント削除（退会）。取り返しがつかない操作のため、まず内容確認 → 現在のパスワード入力の2段階にする。
Future<void> _showAccountDeletionFlow(BuildContext context, WidgetRef ref) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('アカウントを削除しますか？'),
      content: const Text(
        'アカウントを削除すると、登録した人物・接点・メモなどのデータがすべて完全に削除され、元に戻すことはできません。\n\n'
        'ご契約中のサブスクリプションも同時に解約されます。',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('キャンセル')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('次へ進む'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  final passwordController = TextEditingController();
  final formKey = GlobalKey<FormState>();
  bool isSubmitting = false;
  String? errorMessage;

  final deleted = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('本人確認'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('削除を実行するため、現在のパスワードを入力してください。'),
              const SizedBox(height: 12),
              TextFormField(
                controller: passwordController,
                autofocus: true,
                obscureText: true,
                decoration: const InputDecoration(labelText: '現在のパスワード', border: OutlineInputBorder()),
                validator: (v) => (v == null || v.isEmpty) ? '現在のパスワードを入力してください' : null,
              ),
              if (errorMessage != null) ...[
                const SizedBox(height: 8),
                Text(errorMessage!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: isSubmitting ? null : () => Navigator.of(context).pop(false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: isSubmitting
                ? null
                : () async {
                    if (!formKey.currentState!.validate()) return;
                    setState(() {
                      isSubmitting = true;
                      errorMessage = null;
                    });
                    final error = await ref
                        .read(authSessionProvider.notifier)
                        .deleteAccount(currentPassword: passwordController.text);
                    if (error == null) {
                      if (context.mounted) Navigator.of(context).pop(true);
                    } else {
                      setState(() {
                        isSubmitting = false;
                        errorMessage = error;
                      });
                    }
                  },
            child: isSubmitting
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('削除する'),
          ),
        ],
      ),
    ),
  );
  passwordController.dispose();
  // 成功時はauthSessionのstateがunauthenticatedになり、go_routerが自動的にログイン画面へ遷移する。
  if (deleted == true && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('アカウントを削除しました。')));
  }
}

// 表示名の変更。相互人脈登録・通知設定は現在値をそのまま維持して送る。
Future<void> _showEditDisplayNameDialog(BuildContext context, WidgetRef ref, UserSettings settings) async {
  final controller = TextEditingController(text: settings.displayName);
  final formKey = GlobalKey<FormState>();
  bool isSubmitting = false;
  String? errorMessage;

  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('表示名を変更'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(labelText: '表示名', border: OutlineInputBorder()),
                validator: (v) => (v == null || v.trim().isEmpty) ? '表示名を入力してください' : null,
              ),
              if (errorMessage != null) ...[
                const SizedBox(height: 8),
                Text(errorMessage!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: isSubmitting ? null : () => Navigator.of(context).pop(false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: isSubmitting
                ? null
                : () async {
                    if (!formKey.currentState!.validate()) return;
                    setState(() {
                      isSubmitting = true;
                      errorMessage = null;
                    });
                    try {
                      await ref.read(personRepositoryProvider).updateMySettings(
                            displayName: controller.text.trim(),
                            allowMutualRegistration: settings.allowMutualRegistration,
                            allowNotifications: settings.allowNotifications,
                          );
                      if (context.mounted) Navigator.of(context).pop(true);
                    } catch (e) {
                      setState(() {
                        isSubmitting = false;
                        errorMessage = '更新に失敗しました: $e';
                      });
                    }
                  },
            child: isSubmitting
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('保存'),
          ),
        ],
      ),
    ),
  );
  controller.dispose();
  if (saved == true) {
    ref.invalidate(userSettingsProvider);
  }
}

// メールアドレスの変更。本人確認のため現在のパスワードが必須。
Future<void> _showChangeEmailDialog(BuildContext context, WidgetRef ref, UserSettings settings) async {
  final emailController = TextEditingController(text: settings.email);
  final passwordController = TextEditingController();
  final formKey = GlobalKey<FormState>();
  bool isSubmitting = false;
  String? errorMessage;

  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('メールアドレスを変更'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: emailController,
                autofocus: true,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: '新しいメールアドレス', border: OutlineInputBorder()),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'メールアドレスを入力してください';
                  if (!v.contains('@')) return '正しいメールアドレスを入力してください';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: passwordController,
                obscureText: true,
                decoration: const InputDecoration(labelText: '現在のパスワード（本人確認）', border: OutlineInputBorder()),
                validator: (v) => (v == null || v.isEmpty) ? '現在のパスワードを入力してください' : null,
              ),
              if (errorMessage != null) ...[
                const SizedBox(height: 8),
                Text(errorMessage!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: isSubmitting ? null : () => Navigator.of(context).pop(false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: isSubmitting
                ? null
                : () async {
                    if (!formKey.currentState!.validate()) return;
                    setState(() {
                      isSubmitting = true;
                      errorMessage = null;
                    });
                    final error = await ref.read(authSessionProvider.notifier).changeEmail(
                          newEmail: emailController.text.trim(),
                          currentPassword: passwordController.text,
                        );
                    if (error == null) {
                      if (context.mounted) Navigator.of(context).pop(true);
                    } else {
                      setState(() {
                        isSubmitting = false;
                        errorMessage = error;
                      });
                    }
                  },
            child: isSubmitting
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('保存'),
          ),
        ],
      ),
    ),
  );
  emailController.dispose();
  passwordController.dispose();
  if (saved == true) {
    ref.invalidate(userSettingsProvider);
  }
}

// パスワードの変更（ログイン中に実施）。「パスワードをお忘れですか」とは別フロー。
Future<void> _showChangePasswordDialog(BuildContext context, WidgetRef ref) async {
  final currentController = TextEditingController();
  final newController = TextEditingController();
  final confirmController = TextEditingController();
  final formKey = GlobalKey<FormState>();
  bool isSubmitting = false;
  String? errorMessage;

  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('パスワードを変更'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: currentController,
                autofocus: true,
                obscureText: true,
                decoration: const InputDecoration(labelText: '現在のパスワード', border: OutlineInputBorder()),
                validator: (v) => (v == null || v.isEmpty) ? '現在のパスワードを入力してください' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: newController,
                obscureText: true,
                decoration: const InputDecoration(labelText: '新しいパスワード（8文字以上）', border: OutlineInputBorder()),
                validator: (v) => (v == null || v.length < 8) ? 'パスワードは8文字以上で設定してください' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: confirmController,
                obscureText: true,
                decoration: const InputDecoration(labelText: '新しいパスワード（確認）', border: OutlineInputBorder()),
                validator: (v) => (v != newController.text) ? 'パスワードが一致しません' : null,
              ),
              if (errorMessage != null) ...[
                const SizedBox(height: 8),
                Text(errorMessage!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: isSubmitting ? null : () => Navigator.of(context).pop(false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: isSubmitting
                ? null
                : () async {
                    if (!formKey.currentState!.validate()) return;
                    setState(() {
                      isSubmitting = true;
                      errorMessage = null;
                    });
                    final error = await ref.read(authSessionProvider.notifier).changePassword(
                          currentPassword: currentController.text,
                          newPassword: newController.text,
                        );
                    if (error == null) {
                      if (context.mounted) Navigator.of(context).pop(true);
                    } else {
                      setState(() {
                        isSubmitting = false;
                        errorMessage = error;
                      });
                    }
                  },
            child: isSubmitting
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('保存'),
          ),
        ],
      ),
    ),
  );
  currentController.dispose();
  newController.dispose();
  confirmController.dispose();
  if (saved == true && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('パスワードを変更しました')));
  }
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
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('アカウント', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          userSettingsAsync.when(
            loading: () => const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()),
            error: (err, st) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text('アカウント情報の取得に失敗しました: $err', style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ),
            data: (settings) => Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(settings.displayName),
                  subtitle: Text(settings.email),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showEditDisplayNameDialog(context, ref, settings),
                ),
                ListTile(
                  leading: const Icon(Icons.email_outlined),
                  title: const Text('メールアドレスを変更'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showChangeEmailDialog(context, ref, settings),
                ),
                ListTile(
                  leading: const Icon(Icons.lock_outline),
                  title: const Text('パスワードを変更'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showChangePasswordDialog(context, ref),
                ),
              ],
            ),
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
                  await ref.read(personRepositoryProvider).updateMySettings(
                        displayName: settings.displayName,
                        allowMutualRegistration: v,
                        allowNotifications: settings.allowNotifications,
                      );
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
            child: Text('通知', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          userSettingsAsync.when(
            loading: () => const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()),
            error: (err, st) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text('設定の取得に失敗しました: $err', style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ),
            data: (settings) => SwitchListTile(
              title: const Text('お知らせ・アップデート情報の通知'),
              subtitle: const Text('メールアドレス変更・パスワード変更などのセキュリティ通知は、この設定に関わらず常に送信されます'),
              value: settings.allowNotifications,
              onChanged: (v) async {
                try {
                  await ref.read(personRepositoryProvider).updateMySettings(
                        displayName: settings.displayName,
                        allowMutualRegistration: settings.allowMutualRegistration,
                        allowNotifications: v,
                      );
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
            title: const Text('アカウント削除'),
            onTap: () => _showAccountDeletionFlow(context, ref),
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
