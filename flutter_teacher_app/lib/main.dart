/// Point d'entrée de l'application SchoolTrack — Enseignants.
/// Architecture offline-first (US 2.x, US 3.x).
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'features/trips/screens/trip_list_screen.dart';

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
    // US 2.2+ : écrans de scan et présences (à ajouter)
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
