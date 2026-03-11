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
import 'features/token_stock/screens/token_stock_screen.dart';
import 'features/audit/screens/audit_log_screen.dart';
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
          textTheme: const TextTheme(
            // Titres
            titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            titleMedium: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
            titleSmall: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            // Corps de texte
            bodyLarge: TextStyle(fontSize: 13),
            bodyMedium: TextStyle(fontSize: 12.5),
            bodySmall: TextStyle(fontSize: 11.5),
            // Labels (boutons, champs)
            labelLarge: TextStyle(fontSize: 13),
            labelMedium: TextStyle(fontSize: 12),
            labelSmall: TextStyle(fontSize: 11),
          ),
          dataTableTheme: const DataTableThemeData(
            headingTextStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            dataTextStyle: TextStyle(fontSize: 12),
            dataRowMinHeight: 40,
            dataRowMaxHeight: 48,
          ),
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

      // US 6.2 — Routes admin-only : redirige les non-admin vers /students
      if (loggedIn && !auth.isAdmin) {
        const adminOnlyPaths = ['/students/import', '/tokens', '/tokens/stock', '/users', '/audit'];
        if (adminOnlyPaths.contains(state.uri.path)) return '/students';
      }

      return null;
    },
    routes: [
      // Login
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),

      // Redirection racine : admin → import, autres → liste eleves
      GoRoute(
        path: '/',
        redirect: (_, __) => auth.isAdmin ? '/students/import' : '/students',
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

      // US 1.4 — Stock de bracelets
      GoRoute(
        path: '/tokens/stock',
        builder: (context, state) => AppScaffold(
          pageTitle: 'Stock de bracelets',
          child: const TokenStockScreen(),
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

      // US 6.4 — Logs d'audit
      GoRoute(
        path: '/audit',
        builder: (context, state) => AppScaffold(
          pageTitle: 'Logs d\'audit',
          child: const AuditLogScreen(),
        ),
      ),
    ],
  );
}
