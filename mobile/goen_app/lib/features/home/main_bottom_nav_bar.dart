import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// ホーム画面（S-002）の5タブに対応するアイコン・ラベルの定義。
/// [MainBottomNavBar]と[HomeScreen]の双方から参照する。
class MainNavTab {
  const MainNavTab({required this.icon, required this.selectedIcon, required this.label});
  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

const mainNavTabs = [
  MainNavTab(icon: Icons.dashboard_outlined, selectedIcon: Icons.dashboard, label: 'ダッシュボード'),
  MainNavTab(icon: Icons.people_outline, selectedIcon: Icons.people, label: '人物一覧'),
  MainNavTab(icon: Icons.person_add_alt_1_outlined, selectedIcon: Icons.person_add_alt_1, label: '登録'),
  MainNavTab(icon: Icons.hub_outlined, selectedIcon: Icons.hub, label: '人脈マップ'),
  MainNavTab(icon: Icons.edit_note_outlined, selectedIcon: Icons.edit_note, label: '例文作成'),
];

/// 画面下部のタブバー。ホーム画面（S-002）の5タブ切り替えだけでなく、人物カルテ・AI相談など
/// ホームから遷移した先の閲覧系画面でも常に表示し、いつでも主要画面へ戻れるようにする
/// （入力フォーム・カメラ撮影画面など、離脱で入力内容が失われる画面には配置しない）。
///
/// [onTap]を省略した場合、タップ時は`/home?tab=N`へ遷移する（ホーム画面が該当タブを開いた状態で
/// 再構築される）。ホーム画面自身がこのバーを使う場合は、画面遷移を伴わないローカルなタブ切り替えを
/// 行うため[onTap]を明示的に渡す。
class MainBottomNavBar extends StatelessWidget {
  const MainBottomNavBar({super.key, required this.selectedIndex, this.onTap});

  final int selectedIndex;
  final ValueChanged<int>? onTap;

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: selectedIndex,
      onDestinationSelected: onTap ?? (i) => context.go('/home?tab=$i'),
      destinations: [
        for (final tab in mainNavTabs)
          NavigationDestination(
            icon: Icon(tab.icon),
            selectedIcon: Icon(tab.selectedIcon),
            label: tab.label,
          ),
      ],
    );
  }
}
