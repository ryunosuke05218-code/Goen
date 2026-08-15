import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/auth_session.dart';
import 'core/display_settings.dart';
import 'core/providers.dart';
import 'features/ai_assistant/ai_assistant_history_screen.dart';
import 'features/ai_assistant/ai_assistant_screen.dart';
import 'features/auth/login_screen.dart';
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
import 'features/persons/add_relation_screen.dart';
import 'features/persons/contact_detail_screen.dart';
import 'features/persons/person_card_capture_screen.dart';
import 'features/persons/person_detail_screen.dart';
import 'features/persons/person_edit_screen.dart';
import 'features/persons/person_list_screen.dart';
import 'features/persons/person_network_screen.dart';
import 'features/persons/person_register_screen.dart';
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

final routerProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = _RouterRefreshNotifier(ref);
  ref.onDispose(refreshNotifier.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refreshNotifier,
    redirect: (context, state) {
      final auth = ref.read(authSessionProvider);
      final loggingIn = state.matchedLocation == '/login';

      if (auth.status == AuthStatus.unknown) {
        return state.matchedLocation == '/' ? null : '/';
      }
      if (auth.status == AuthStatus.unauthenticated) {
        return loggingIn ? null : '/login';
      }
      if (auth.status == AuthStatus.locked) {
        return state.matchedLocation == '/unlock' ? null : '/unlock';
      }
      // authenticated
      if (loggingIn || state.matchedLocation == '/' || state.matchedLocation == '/unlock') {
        return '/home';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (context, state) => const _SplashScreen()),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(path: '/unlock', builder: (context, state) => const UnlockScreen()),
      GoRoute(
        path: '/home',
        builder: (context, state) {
          final tab = int.tryParse(state.uri.queryParameters['tab'] ?? '') ?? 0;
          return HomeScreen(initialIndex: tab.clamp(0, mainNavTabs.length - 1));
        },
      ),
      GoRoute(path: '/dashboard', builder: (context, state) => const DashboardScreen()),
      GoRoute(path: '/persons', builder: (context, state) => const PersonListScreen()),
      GoRoute(path: '/persons/new', builder: (context, state) => const PersonRegisterScreen()),
      GoRoute(
        path: '/persons/new/confirm',
        builder: (context, state) => PersonRegisterConfirmScreen(draft: state.extra as OcrDraft),
      ),
      GoRoute(
        path: '/persons/:id',
        builder: (context, state) => PersonDetailScreen(personId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/persons/:id/voice-memo',
        builder: (context, state) => VoiceMemoScreen(personId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/persons/:id/network',
        builder: (context, state) => PersonNetworkScreen(rootPersonId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/persons/:id/relations/new',
        builder: (context, state) => AddRelationScreen(personId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/persons/:id/edit',
        builder: (context, state) => PersonEditScreen(person: state.extra as PersonDetail),
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
      GoRoute(path: '/network-map/ai-assistant', builder: (context, state) => const AiAssistantScreen()),
      GoRoute(
        path: '/network-map/ai-assistant/history',
        builder: (context, state) => const AiAssistantHistoryScreen(),
      ),
      GoRoute(path: '/network-map/other-user', builder: (context, state) => const OtherUserNetworkScreen()),
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
      GoRoute(path: '/intro-letter/history', builder: (context, state) => const IntroLetterHistoryScreen()),
      GoRoute(path: '/settings', builder: (context, state) => const SettingsScreen()),
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
