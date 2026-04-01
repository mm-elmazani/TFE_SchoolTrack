/// Shell principal avec NavigationBar Material 3 (bottom nav).
///
/// 3 branches :
///   - Voyages (index 0)
///   - Sync    (index 1)
///   - Admin   (index 2, visible uniquement pour DIRECTION / ADMIN_TECH)
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../auth/providers/auth_provider.dart';

class MainShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const MainShell({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context) {
    final isAdmin = context.watch<AuthProvider>().isAdmin;
    final currentIndex = navigationShell.currentIndex;

    // Si non-admin et index = 2 (admin), clamp a 0
    final safeIndex = (!isAdmin && currentIndex >= 2) ? 0 : currentIndex;

    final destinations = <NavigationDestination>[
      const NavigationDestination(
        icon: Icon(Icons.directions_bus_outlined),
        selectedIcon: Icon(Icons.directions_bus),
        label: 'Voyages',
      ),
      const NavigationDestination(
        icon: Icon(Icons.sync_outlined),
        selectedIcon: Icon(Icons.sync),
        label: 'Sync',
      ),
      if (isAdmin)
        const NavigationDestination(
          icon: Icon(Icons.admin_panel_settings_outlined),
          selectedIcon: Icon(Icons.admin_panel_settings),
          label: 'Admin',
        ),
    ];

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: safeIndex,
        onDestinationSelected: (index) => navigationShell.goBranch(
          index,
          initialLocation: index == navigationShell.currentIndex,
        ),
        destinations: destinations,
      ),
    );
  }
}
