import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'features/auth/providers/auth_provider.dart';
import 'features/auth/screens/login_screen.dart';
import 'features/classes/screens/class_list_screen.dart';
import 'features/students/screens/student_import_screen.dart';
import 'features/students/screens/student_list_screen.dart';
import 'features/trips/screens/trip_list_screen.dart';
import 'features/tokens/screens/token_screen.dart';
import 'features/users/screens/user_list_screen.dart';
import 'shared/widgets/app_scaffold.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final authProvider = AuthProvider();
  await authProvider.init();
  runApp(SchoolTrackDashboardApp(authProvider: authProvider));
}

/// Application principale du dashboard SchoolTrack — Direction.
class SchoolTrackDashboardApp extends StatelessWidget {
  final AuthProvider authProvider;

  const SchoolTrackDashboardApp({super.key, required this.authProvider});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: authProvider,
      child: MaterialApp.router(
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
        routerConfig: _buildRouter(authProvider),
      ),
    );
  }
}

/// Configuration du routeur GoRouter avec guard d'authentification.
GoRouter _buildRouter(AuthProvider auth) {
  return GoRouter(
    initialLocation: '/',
    refreshListenable: auth,
    redirect: (context, state) {
      final loggedIn = auth.isAuthenticated;
      final onLogin = state.uri.path == '/login';

      if (!loggedIn && !onLogin) return '/login';
      if (loggedIn && onLogin) return '/';
      return null;
    },
    routes: [
      // Login
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),

      // Redirection racine vers l'ecran d'import eleves
      GoRoute(
        path: '/',
        redirect: (_, __) => '/students/import',
      ),

      // US 1.1 — Import CSV eleves
      GoRoute(
        path: '/students/import',
        builder: (context, state) => AppScaffold(
          pageTitle: 'Import élèves',
          child: const StudentImportScreen(),
        ),
      ),

      // US 1.3 — Liste des eleves
      GoRoute(
        path: '/students',
        builder: (context, state) => AppScaffold(
          pageTitle: 'Élèves',
          child: const StudentListScreen(),
        ),
      ),

      // US 1.2 — Voyages (liste + CRUD)
      GoRoute(
        path: '/trips',
        builder: (context, state) => AppScaffold(
          pageTitle: 'Voyages scolaires',
          child: const TripListScreen(),
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

      // US 1.5 — Assignation bracelets NFC/QR
      GoRoute(
        path: '/tokens',
        builder: (context, state) => AppScaffold(
          pageTitle: 'Bracelets NFC/QR',
          child: const TokenScreen(),
        ),
      ),

      // US 6.1 — Gestion utilisateurs (Direction)
      GoRoute(
        path: '/users',
        builder: (context, state) => AppScaffold(
          pageTitle: 'Utilisateurs',
          child: const UserListScreen(),
        ),
      ),
    ],
  );
}
