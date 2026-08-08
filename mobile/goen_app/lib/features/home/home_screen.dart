import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// S-002 ホーム画面。直近の接点・クイック登録ボタンを表示する。
/// 直近接点の実データ連携は今後のフェーズで拡張する。通知機能（F-012）は廃止し、紹介文作成（F-026）に置き換えた。
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('GOEN'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.person_add_alt_1_outlined),
              title: const Text('人物を登録'),
              subtitle: const Text('F-007 / F-002: 名刺撮影・手入力を切り替えて登録できます'),
              onTap: () => context.push('/persons/new'),
            ),
          ),
          const SizedBox(height: 8),
          _QuickNav(icon: Icons.people_outline, label: '人物一覧', route: '/persons'),
          _QuickNav(icon: Icons.hub_outlined, label: '人脈マップ', route: '/network-map'),
          _QuickNav(icon: Icons.edit_note_outlined, label: '例文作成', route: '/intro-letter'),
        ],
      ),
    );
  }
}

class _QuickNav extends StatelessWidget {
  const _QuickNav({required this.icon, required this.label, required this.route});

  final IconData icon;
  final String label;
  final String route;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(label),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push(route),
      ),
    );
  }
}
