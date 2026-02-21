import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'features/classes/screens/class_list_screen.dart';
import 'features/students/screens/student_import_screen.dart';
import 'features/students/screens/student_list_screen.dart';
import 'shared/widgets/app_scaffold.dart';

void main() {
  runApp(const SchoolTrackDashboardApp());
}

/// Application principale du dashboard SchoolTrack — Direction.
/// Utilise GoRouter pour le routing et Material 3 pour le thème.
class SchoolTrackDashboardApp extends StatelessWidget {
  const SchoolTrackDashboardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'SchoolTrack — Direction',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1565C0), // Bleu EPHEC
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      routerConfig: _router,
    );
  }
}

/// Configuration du routeur GoRouter.
/// Toutes les routes du dashboard Direction sont définies ici.
final GoRouter _router = GoRouter(
  initialLocation: '/',
  routes: [
    // Redirection racine vers l'écran d'import élèves
    GoRoute(
      path: '/',
      redirect: (_, __) => '/students/import',
    ),

    // US 1.1 — Import CSV élèves
    GoRoute(
      path: '/students/import',
      builder: (context, state) => AppScaffold(
        pageTitle: 'Import élèves',
        child: const StudentImportScreen(),
      ),
    ),

    // US 1.3 — Liste des élèves
    GoRoute(
      path: '/students',
      builder: (context, state) => AppScaffold(
        pageTitle: 'Élèves',
        child: const StudentListScreen(),
      ),
    ),

    // US 1.2 — Voyages (placeholder, à implémenter)
    GoRoute(
      path: '/trips',
      builder: (context, state) => AppScaffold(
        pageTitle: 'Voyages',
        child: const _PlaceholderScreen(title: 'Gestion des voyages'),
      ),
    ),

    // US 1.3 — Classes scolaires
    GoRoute(
      path: '/classes',
      builder: (context, state) => AppScaffold(
        pageTitle: 'Classes',
        child: const ClassListScreen(),
      ),
    ),

    // US 1.5 — Bracelets/Tokens (placeholder, à implémenter)
    GoRoute(
      path: '/tokens',
      builder: (context, state) => AppScaffold(
        pageTitle: 'Bracelets NFC/QR',
        child: const _PlaceholderScreen(title: 'Assignation des bracelets'),
      ),
    ),
  ],
);

/// Écran placeholder pour les routes non encore implémentées.
class _PlaceholderScreen extends StatelessWidget {
  final String title;

  const _PlaceholderScreen({required this.title});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.construction, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            title,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'À implémenter dans une prochaine session.',
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}
