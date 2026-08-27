import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/auth_session.dart';
import 'core/display_settings.dart';
import 'core/providers.dart';
import 'features/ai_assistant/ai_assistant_history_screen.dart';
import 'features/ai_assistant/ai_assistant_screen.dart';
import 'features/auth/forgot_password_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/reset_password_screen.dart';
import 'features/auth/subscription_required_screen.dart';
import 'features/auth/unlock_screen.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/home/home_screen.dart';
import 'features/home/main_bottom_nav_bar.dart';
import 'features/intro_letter/intro_letter_history_screen.dart';
import 'features/intro_letter/intro_letter_screen.dart';
import 'features/masters/master_management_screen.dart';
import 'features/network_map/network_map_screen.dart';
import 'features/network_map/other_user_network_screen.dart';
import 'features/persons/models/person_models.dart';
import 'features/persons/contact_detail_screen.dart';
import 'features/persons/person_card_capture_screen.dart';
import 'features/persons/person_detail_screen.dart';
import 'features/persons/person_edit_screen.dart';
import 'features/persons/person_list_screen.dart';
import 'features/persons/person_network_screen.dart';
import 'features/persons/person_register_screen.dart';
import 'features/persons/self_person_register_screen.dart';
import 'features/persons/voice_memo_screen.dart';
import 'features/settings/settings_screen.dart';

// authSessionProviderの変化をGoRouterへ伝える橋渡し。
// routerProvider自体はauthSessionProviderをwatchしない（rebuildでNavigator状態を失わないため）。
// 代わりにrefreshListenable経由でredirectのみ再評価させる（go_router + riverpod の標準的な統合方法）。
class _RouterRefreshNotifier extends ChangeNotifier {
  _RouterRefreshNotifier(Ref ref) {
    ref.listen(authSessionProvider, (previous, next) => notifyListeners());
  }
}

// 未ログインでもアクセスしてよい画面（それ以外は/loginへリダイレクトする）
// F-001拡張: アプリ内での新規登録は廃止（Web完結の会員登録・Stripe契約フローに一本化したため）。
const _publicRoutes = {'/login', '/forgot-password', '/reset-password'};

final routerProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = _RouterRefreshNotifier(ref);
  ref.onDispose(refreshNotifier.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refreshNotifier,
    redirect: (context, state) {
      final auth = ref.read(authSessionProvider);
      final onPublicRoute = _publicRoutes.contains(state.matchedLocation);

      if (auth.status == AuthStatus.unknown) {
        return state.matchedLocation == '/' ? null : '/';
      }
      if (auth.status == AuthStatus.unauthenticated) {
        return onPublicRoute ? null : '/login';
      }
      if (auth.status == AuthStatus.locked) {
        return state.matchedLocation == '/unlock' ? null : '/unlock';
      }
      if (auth.status == AuthStatus.subscriptionRequired) {
        return state.matchedLocation == '/subscription-required' ? null : '/subscription-required';
      }
      // authenticated
      if (onPublicRoute ||
          state.matchedLocation == '/' ||
          state.matchedLocation == '/unlock' ||
          state.matchedLocation == '/subscription-required') {
        return '/home';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (context, state) => const _SplashScreen()),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(path: '/forgot-password', builder: (context, state) => const ForgotPasswordScreen()),
      GoRoute(
        path: '/reset-password',
        builder: (context, state) => ResetPasswordScreen(initialEmail: state.extra as String?),
      ),
      GoRoute(path: '/unlock', builder: (context, state) => const UnlockScreen()),
      GoRoute(path: '/subscription-required', builder: (context, state) => const SubscriptionRequiredScreen()),
      GoRoute(
        path: '/home',
        builder: (context, state) {
          final tab = int.tryParse(state.uri.queryParameters['tab'] ?? '') ?? 0;
          return HomeScreen(initialIndex: tab.clamp(0, mainNavTabs.length - 1));
        },
      ),
      GoRoute(path: '/dashboard', builder: (context, state) => const DashboardScreen()),
      GoRoute(path: '/persons', builder: (context, state) => const PersonListScreen()),
      GoRoute(
        path: '/persons/new',
        // 人物一覧の「＋」から独立した画面として開いた場合も、ホーム画面のタブとして開いた場合と同じく
        // 下部メニューを表示する（HomeScreenのIndexedStackタブとして使う場合はHomeScreen側のbottomNavigationBar
        // が既にあるため、PersonRegisterScreen自体には持たせず、ここでルート単位でラップする）。
        builder: (context, state) => Scaffold(
          body: const PersonRegisterScreen(returnPath: '/home?tab=1'),
          bottomNavigationBar: const MainBottomNavBar(selectedIndex: 2),
        ),
      ),
      GoRoute(
        path: '/persons/new/confirm',
        builder: (context, state) {
          final (draft, returnPath) = state.extra as (OcrDraft, String?);
          return PersonRegisterConfirmScreen(draft: draft, returnPath: returnPath);
        },
      ),
      GoRoute(
        path: '/persons/me/new',
        builder: (context, state) => SelfPersonRegisterScreen(
          returnPath: state.extra is String ? state.extra as String : null,
        ),
      ),
      GoRoute(
        path: '/persons/:id',
        builder: (context, state) => PersonDetailScreen(
          personId: state.pathParameters['id']!,
          returnPath: state.extra is String ? state.extra as String : null,
        ),
      ),
      GoRoute(
        path: '/persons/:id/voice-memo',
        builder: (context, state) => VoiceMemoScreen(
          personId: state.pathParameters['id']!,
          returnPath: state.extra is String ? state.extra as String : null,
        ),
      ),
      GoRoute(
        path: '/persons/:id/network',
        builder: (context, state) => PersonNetworkScreen(rootPersonId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/persons/:id/edit',
        builder: (context, state) {
          final (person, returnPath) = state.extra as (PersonDetail, String?);
          return PersonEditScreen(person: person, returnPath: returnPath);
        },
      ),
      GoRoute(
        path: '/persons/:id/contacts/:contactId',
        builder: (context, state) {
          final (contact, personName) = state.extra as (ContactItem, String);
          return ContactDetailScreen(
            personId: state.pathParameters['id']!,
            personName: personName,
            contact: contact,
          );
        },
      ),
      GoRoute(path: '/network-map', builder: (context, state) => const NetworkMapScreen()),
      GoRoute(
        path: '/network-map/ai-assistant',
        builder: (context, state) => AiAssistantScreen(
          returnPath: state.extra is String ? state.extra as String : null,
        ),
      ),
      GoRoute(
        path: '/network-map/ai-assistant/history',
        builder: (context, state) => const AiAssistantHistoryScreen(),
      ),
      GoRoute(
        path: '/network-map/other-user',
        builder: (context, state) => OtherUserNetworkScreen(
          returnPath: state.extra is String ? state.extra as String : null,
        ),
      ),
      GoRoute(
        path: '/intro-letter',
        builder: (context, state) {
          // F-031: AI指示画面から対象人物・要件を引き継いで開始する場合に使う
          final extra = state.extra;
          if (extra is IntroLetterPrefill) {
            return IntroLetterScreen(
              initialPersonId: extra.personId,
              initialPersonName: extra.personName,
              initialRequirement: extra.requirement,
            );
          }
          return const IntroLetterScreen();
        },
      ),
      GoRoute(
        path: '/intro-letter/history',
        builder: (context, state) => IntroLetterHistoryScreen(
          returnPath: state.extra is String ? state.extra as String : null,
        ),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => SettingsScreen(
          returnPath: state.extra is String ? state.extra as String : null,
        ),
      ),
      GoRoute(path: '/masters/manage', builder: (context, state) => const MasterManagementScreen()),
    ],
  );
});

class GoenApp extends ConsumerWidget {
  const GoenApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final displaySettings = ref.watch(displaySettingsProvider);

    return MaterialApp.router(
      title: 'GOEN',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      darkTheme: ThemeData(colorSchemeSeed: Colors.indigo, brightness: Brightness.dark, useMaterial3: true),
      themeMode: displaySettings.themeMode,
      routerConfig: router,
      builder: (context, child) {
        final mediaQuery = MediaQuery.of(context);
        return MediaQuery(
          data: mediaQuery.copyWith(
            textScaler: TextScaler.linear(displaySettings.textScale.factor),
          ),
          child: child!,
        );
      },
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
