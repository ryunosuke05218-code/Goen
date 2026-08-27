import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key, this.initialIndex = 0});

  final int initialIndex;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  late int _index = widget.initialIndex;

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // '/home'は他画面から`context.go('/home?tab=N')`で戻ってきた際、スタック上に残っていた
    // 既存のStateがそのまま再利用される（go_routerの既定のpageKeyはクエリパラメータを含まずpath基準の
    // ため、'/home'ページの実体は最初に作られたときのまま保持され続ける）。
    // ここで`oldWidget.initialIndex`と比較すると、widgetの構成引数自体は毎回`initialIndex: 0`のまま
    // 変化していないケース（＝最初にホームへ入った際のタブが0だった場合）で正しく機能しない：
    // 例えばホーム内でタブを1（人物一覧）へローカルにsetState切替→人物カルテへpush→
    // 下部メニューの「ダッシュボード」(tab=0)をタップ、というケースでは
    // widget.initialIndexもoldWidget.initialIndexも共に0のままなので変化なしと判定され、
    // 実際には1のまま止まっていた_indexが更新されない。
    // 正しくは「現在表示中のタブ（_index）」と比較し、ズレていれば必ず追従させる。
    if (widget.initialIndex != _index) {
      _selectTab(widget.initialIndex);
    }
  }

  // ダッシュボードはIndexedStackで裏側に保持されたままのため、他のタブ（人物一覧・登録など）で
  // 人物や接点を追加しても自動では再取得されない。ダッシュボードへ切り替わるたびに再取得することで、
  // 「登録人数を増やしても反映されない」「接点記録を作成しても表示されない」という古いデータ表示を防ぐ。
  void _selectTab(int index) {
    setState(() => _index = index);
    if (index == 0) {
      // ref.invalidateを同期的に呼ぶと、didUpdateWidget経由（他画面から人脈マップ経由で人物カルテを
      // 開いた直後など、まだ画面遷移のビルドが進行中のタイミング）で呼ばれた場合に、進行中のビルド中に
      // 別ウィジェット（UncontrolledProviderScope）のsetStateを誘発してしまい、
      // 「setState() or markNeedsBuild() called during build」から要素ツリーが壊れ、
      // 遷移直後に一時的にエラー画面が表示されることがあった。フレーム確定後まで遅延させて回避する。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.invalidate(dashboardProvider);
      });
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
          IntroLetterScreen(returnPath: '/home?tab=4'),
        ],
      ),
      bottomNavigationBar: MainBottomNavBar(
        selectedIndex: _index,
        onTap: _selectTab,
      ),
    );
  }
}
