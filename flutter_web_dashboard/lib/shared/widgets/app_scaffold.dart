import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../features/auth/providers/auth_provider.dart';

/// Structure commune du dashboard (sidebar + zone de contenu).
/// Utilisée comme wrapper pour tous les écrans du dashboard Direction.
class AppScaffold extends StatelessWidget {
  /// Contenu principal de l'écran affiché à droite de la sidebar
  final Widget child;

  /// Titre affiché dans la barre de l'écran courant
  final String pageTitle;

  const AppScaffold({
    super.key,
    required this.child,
    required this.pageTitle,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // Sidebar de navigation
          _AppSidebar(currentPath: GoRouterState.of(context).uri.path),

          // Séparateur vertical
          const VerticalDivider(width: 1),

          // Zone de contenu principale
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Barre supérieure
                _TopBar(title: pageTitle),

                // Zone de contenu (l'écran gère lui-même son scroll si besoin)
                Expanded(child: child),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Barre supérieure avec le titre de la page
class _TopBar extends StatelessWidget {
  final String title;

  const _TopBar({required this.title});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}

/// Sidebar de navigation avec NavigationRail adapté au web
class _AppSidebar extends StatelessWidget {
  final String currentPath;

  const _AppSidebar({required this.currentPath});

  /// Construit la liste de nav items filtree selon le role de l'utilisateur.
  static List<_NavItem> _navItemsForRole(bool isAdmin) {
    return [
      if (isAdmin)
        const _NavItem(
          path: '/students/import',
          icon: Icons.upload_file,
          label: 'Import élèves',
        ),
      const _NavItem(
        path: '/students',
        icon: Icons.people_outline,
        label: 'Élèves',
      ),
      const _NavItem(
        path: '/classes',
        icon: Icons.class_,
        label: 'Classes',
      ),
      const _NavItem(
        path: '/trips',
        icon: Icons.directions_bus,
        label: 'Voyages',
      ),
      if (isAdmin)
        const _NavItem(
          path: '/tokens',
          icon: Icons.badge,
          label: 'Bracelets',
        ),
      if (isAdmin)
        const _NavItem(
          path: '/users',
          icon: Icons.manage_accounts,
          label: 'Utilisateurs',
        ),
      if (isAdmin)
        const _NavItem(
          path: '/audit',
          icon: Icons.history,
          label: 'Logs d\'audit',
        ),
    ];
  }

  int _selectedIndex(List<_NavItem> items) {
    for (var i = 0; i < items.length; i++) {
      if (currentPath == items[i].path) return i;
    }
    for (var i = 0; i < items.length; i++) {
      if (currentPath.startsWith(items[i].path)) return i;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final navItems = _navItemsForRole(auth.isAdmin);
    final selectedIdx = _selectedIndex(navItems);

    return Container(
      width: 200,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Column(
        children: [
          // Logo / titre de l'app
          Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                Icon(
                  Icons.school,
                  color: Theme.of(context).colorScheme.primary,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Text(
                  'SchoolTrack',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Éléments de navigation
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: navItems.length,
              itemBuilder: (context, index) {
                final item = navItems[index];
                final isSelected = index == selectedIdx;
                return ListTile(
                  selected: isSelected,
                  leading: Icon(
                    item.icon,
                    size: 20,
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : Colors.grey.shade600,
                  ),
                  title: Text(
                    item.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.normal,
                      color: isSelected
                          ? Theme.of(context).colorScheme.primary
                          : Colors.grey.shade700,
                    ),
                  ),
                  selectedTileColor:
                      Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  onTap: () => context.go(item.path),
                );
              },
            ),
          ),

          // Pied de sidebar — utilisateur connecte + deconnexion
          const Divider(height: 1),
          Consumer<AuthProvider>(
            builder: (context, auth, _) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      auth.userDisplayName ?? '',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey.shade700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      auth.userRole ?? '',
                      style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      width: double.infinity,
                      height: 32,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          await auth.logout();
                          if (context.mounted) context.go('/login');
                        },
                        icon: const Icon(Icons.logout, size: 16),
                        label: const Text('Déconnexion', style: TextStyle(fontSize: 12)),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Entrée de navigation dans la sidebar
class _NavItem {
  final String path;
  final IconData icon;
  final String label;

  const _NavItem({
    required this.path,
    required this.icon,
    required this.label,
  });
}
