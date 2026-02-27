/// Point d'entrée de l'application SchoolTrack — Enseignants.
/// Architecture offline-first (US 2.x, US 3.x).
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'features/trips/screens/trip_list_screen.dart';
import 'features/scan/screens/checkpoint_selection_screen.dart';
import 'features/scan/screens/scan_screen.dart';
import 'features/scan/screens/attendance_list_screen.dart';
import 'features/scan/providers/scan_provider.dart';

void main() {
  runApp(const SchoolTrackApp());
}

// ----------------------------------------------------------------
// Router
// ----------------------------------------------------------------

final _router = GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const TripListScreen(),
    ),

    // US 2.2 : sélection checkpoint puis scan
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

    // US 2.3 : suivi temps réel présents/manquants
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

// ----------------------------------------------------------------
// Application
// ----------------------------------------------------------------

class SchoolTrackApp extends StatelessWidget {
  const SchoolTrackApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'SchoolTrack',
      debugShowCheckedModeBanner: false,
      routerConfig: _router,
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
    );
  }
}
