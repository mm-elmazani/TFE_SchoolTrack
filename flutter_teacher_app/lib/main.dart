/// Point d'entree de l'application SchoolTrack — Enseignants.
/// Architecture offline-first (US 2.x, US 3.x).
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'core/services/sync_provider.dart';
import 'features/auth/providers/auth_provider.dart';
import 'features/auth/screens/login_screen.dart';
import 'features/navigation/screens/admin_screen.dart';
import 'features/navigation/screens/main_shell.dart';
import 'features/nfc_encoding/screens/nfc_encoding_screen.dart';
import 'features/nfc_encoding/screens/token_stock_mobile_screen.dart';
import 'features/nfc_test/screens/nfc_test_screen.dart';
import 'features/sync/screens/sync_history_screen.dart';
import 'features/trips/screens/trip_list_screen.dart';
import 'features/trips/screens/trip_summary_screen.dart';
import 'features/scan/screens/checkpoint_selection_screen.dart';
import 'features/scan/screens/scan_screen.dart';
import 'features/scan/screens/attendance_list_screen.dart';
import 'features/scan/providers/scan_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final authProvider = AuthProvider();
  final syncProvider = SyncProvider();
  await authProvider.init();

  // Demarrer l'auto-sync si deja authentifie
  if (authProvider.isAuthenticated) {
    syncProvider.startAutoSync();
  }

  // Ecouter les changements d'auth pour start/stop auto-sync
  authProvider.addListener(() {
    if (authProvider.isAuthenticated) {
      syncProvider.startAutoSync();
    } else {
      syncProvider.stopAutoSync();
    }
  });

  runApp(SchoolTrackApp(authProvider: authProvider, syncProvider: syncProvider));
}

// ----------------------------------------------------------------
// Router
// ----------------------------------------------------------------

GoRouter _buildRouter(AuthProvider auth) {
  return GoRouter(
    refreshListenable: auth,
    redirect: (context, state) {
      final loggedIn = auth.isAuthenticated;
      final onLogin = state.uri.path == '/login';

      if (!loggedIn && !onLogin) return '/login';
      if (loggedIn && onLogin) return '/';
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),

      // Shell principal avec bottom navigation bar
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            MainShell(navigationShell: navigationShell),
        branches: [
          // Branch 0 : Voyages
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/',
                builder: (context, state) => const TripListScreen(),
              ),
            ],
          ),
          // Branch 1 : Sync
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/sync',
                builder: (context, state) => const SyncHistoryScreen(),
              ),
            ],
          ),
          // Branch 2 : Admin
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/admin',
                builder: (context, state) => const AdminScreen(),
              ),
            ],
          ),
        ],
      ),

      // Routes hors du shell (plein ecran)

      // US 1.4 : encodage NFC (Mode Admin)
      GoRoute(
        path: '/nfc-encoding',
        builder: (context, state) => const NfcEncodingScreen(),
      ),

      // US 1.4 : consultation stock bracelets (Mode Admin)
      GoRoute(
        path: '/token-stock',
        builder: (context, state) => const TokenStockMobileScreen(),
      ),

      // Test NFC (Mode Admin)
      GoRoute(
        path: '/nfc-test',
        builder: (context, state) => const NfcTestScreen(),
      ),

      // US 3.1 : historique des synchronisations (standalone avec AppBar)
      GoRoute(
        path: '/sync-history',
        builder: (context, state) => const SyncHistoryScreen(),
      ),

      // Resume voyage + liste eleves (avant checkpoints)
      GoRoute(
        path: '/trip-summary',
        builder: (context, state) {
          final extra = state.extra as Map<String, String>;
          return TripSummaryScreen(
            tripId: extra['tripId']!,
            tripDestination: extra['tripDestination']!,
          );
        },
      ),

      // US 2.2 : selection checkpoint puis scan
      GoRoute(
        path: '/checkpoints',
        builder: (context, state) {
          final extra = state.extra as Map<String, String>;
          return CheckpointSelectionScreen(
            tripId: extra['tripId']!,
            tripDestination: extra['tripDestination']!,
          );
        },
      ),
      GoRoute(
        path: '/scan',
        builder: (context, state) {
          final extra = state.extra as Map<String, String>;
          return ScanScreen(
            tripId: extra['tripId']!,
            tripDestination: extra['tripDestination']!,
            checkpointId: extra['checkpointId']!,
            checkpointName: extra['checkpointName']!,
          );
        },
      ),

      // US 2.3 : suivi temps reel presents/manquants
      GoRoute(
        path: '/attendance',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>;
          return AttendanceListScreen(
            provider: extra['provider'] as ScanProvider,
            checkpointName: extra['checkpointName'] as String,
            tripDestination: extra['tripDestination'] as String,
          );
        },
      ),
    ],
  );
}

// ----------------------------------------------------------------
// Application
// ----------------------------------------------------------------

class SchoolTrackApp extends StatelessWidget {
  final AuthProvider authProvider;
  final SyncProvider syncProvider;

  const SchoolTrackApp({
    super.key,
    required this.authProvider,
    required this.syncProvider,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: authProvider),
        ChangeNotifierProvider.value(value: syncProvider),
      ],
      child: MaterialApp.router(
        title: 'SchoolTrack',
        debugShowCheckedModeBanner: false,
        routerConfig: _buildRouter(authProvider),
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF1A73E8),
            brightness: Brightness.light,
          ),
          useMaterial3: true,
          appBarTheme: const AppBarTheme(
            elevation: 0,
            centerTitle: false,
          ),
          cardTheme: CardThemeData(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
    );
  }
}
