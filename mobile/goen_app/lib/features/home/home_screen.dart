import 'package:flutter/material.dart';

import '../dashboard/dashboard_screen.dart';
import '../intro_letter/intro_letter_screen.dart';
import '../network_map/network_map_screen.dart';
import '../persons/person_list_screen.dart';
import '../persons/person_register_screen.dart';
import 'main_bottom_nav_bar.dart';

/// S-002 ホーム画面。YouTube等と同様、画面下部のタブで主要画面を切り替える構成にしている。
/// 開いたときの初期タブは[initialIndex]（既定はダッシュボード）。各タブの中身はIndexedStackで保持するため、
/// タブを切り替えても入力途中の内容やスクロール位置は消えない。
/// 他の画面（人物カルテ・AI相談など）からタブをタップした場合は`/home?tab=N`への遷移で戻ってくる。
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.initialIndex = 0});

  final int initialIndex;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late int _index = widget.initialIndex;

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // '/home'は他画面から`context.go('/home?tab=N')`で戻ってきた際、スタック上に残っていた
    // 既存のStateがそのまま再利用されることがある（pushされた画面の下に隠れていただけのため）。
    // その場合late初期化は再実行されないので、tabクエリの変化をここで反映する。
    if (widget.initialIndex != oldWidget.initialIndex) {
      setState(() => _index = widget.initialIndex);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [
          DashboardScreen(),
          PersonListScreen(),
          PersonRegisterScreen(),
          NetworkMapScreen(),
          IntroLetterScreen(),
        ],
      ),
      bottomNavigationBar: MainBottomNavBar(
        selectedIndex: _index,
        onTap: (i) => setState(() => _index = i),
      ),
    );
  }
}
