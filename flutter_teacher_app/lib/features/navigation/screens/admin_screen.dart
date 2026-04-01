/// Ecran administration — acces aux outils NFC et deconnexion.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../auth/providers/auth_provider.dart';

class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Administration'),
        backgroundColor: const Color(0xFF1A73E8),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Section outils NFC
          Text(
            'Outils NFC',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade700,
                ),
          ),
          const SizedBox(height: 8),
          _AdminTile(
            icon: Icons.inventory_2,
            title: 'Stock bracelets',
            subtitle: 'Consulter le stock de bracelets NFC',
            color: const Color(0xFF1A73E8),
            onTap: () => context.push('/token-stock'),
          ),
          const SizedBox(height: 8),
          _AdminTile(
            icon: Icons.nfc,
            title: 'Encodage NFC',
            subtitle: 'Encoder un bracelet NFC',
            color: const Color(0xFF0F9D58),
            onTap: () => context.push('/nfc-encoding'),
          ),
          const SizedBox(height: 8),
          _AdminTile(
            icon: Icons.contactless,
            title: 'Test NFC',
            subtitle: 'Tester la lecture NFC',
            color: const Color(0xFFF4B400),
            onTap: () => context.push('/nfc-test'),
          ),

          const SizedBox(height: 32),

          // Deconnexion
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: colorScheme.error,
                side: BorderSide(color: colorScheme.error),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Deconnexion'),
                    content: const Text('Voulez-vous vous deconnecter ?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
                      FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Deconnexion')),
                    ],
                  ),
                );
                if (confirmed == true && context.mounted) {
                  await context.read<AuthProvider>().logout();
                  if (context.mounted) context.go('/login');
                }
              },
              icon: const Icon(Icons.logout),
              label: const Text('Se deconnecter'),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _AdminTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withAlpha(25),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
