/// Point d'entree de l'application SchoolTrack — Enseignants.
/// Architecture offline-first (US 2.x, US 3.x).
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'features/auth/providers/auth_provider.dart';
import 'features/auth/screens/login_screen.dart';
import 'features/nfc_encoding/screens/nfc_encoding_screen.dart';
import 'features/nfc_encoding/screens/token_stock_mobile_screen.dart';
import 'features/nfc_test/screens/nfc_test_screen.dart';
import 'features/trips/screens/trip_list_screen.dart';
import 'features/scan/screens/checkpoint_selection_screen.dart';
import 'features/scan/screens/scan_screen.dart';
import 'features/scan/screens/attendance_list_screen.dart';
import 'features/scan/providers/scan_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final authProvider = AuthProvider();
  await authProvider.init();
  runApp(SchoolTrackApp(authProvider: authProvider));
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

      GoRoute(
        path: '/',
        builder: (context, state) => const TripListScreen(),
      ),

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

  const SchoolTrackApp({super.key, required this.authProvider});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: authProvider,
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
