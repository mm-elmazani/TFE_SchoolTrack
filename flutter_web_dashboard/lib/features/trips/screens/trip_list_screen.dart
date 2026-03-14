import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html; // ignore: deprecated_member_use

import '../../../core/api/api_client.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/trip_provider.dart';
import '../widgets/trip_card.dart';
import '../widgets/trip_form_dialog.dart';

/// Écran US 1.2 — Liste et gestion des voyages scolaires.
/// Conforme à la maquette V1 : stats, recherche, filtre statut, grille 2 colonnes.
class TripListScreen extends StatelessWidget {
  const TripListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => TripProvider()..loadTrips(),
      child: const _TripListBody(),
    );
  }
}

class _TripListBody extends StatelessWidget {
  const _TripListBody();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TripProvider>();
    final isAdmin = context.watch<AuthProvider>().isAdmin;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // En-tête avec titre + bouton "Nouveau voyage"
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  
                  const SizedBox(height: 4),
                  Text(
                    'Gérez tous vos voyages et sorties',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            if (isAdmin && provider.selectedForExport.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: OutlinedButton.icon(
                  onPressed: () => _downloadBulkExport(context),
                  icon: const Icon(Icons.download, size: 18),
                  label: Text('Exporter (${provider.selectedForExport.length})'),
                ),
              ),
            if (isAdmin)
              FilledButton.icon(
                onPressed: () => _openCreateDialog(context),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Nouveau voyage'),
              ),
          ],
        ),
        const SizedBox(height: 24),

        // Barre recherche + filtre statut
        Row(
          children: [
            Expanded(
              child: TextField(
                onChanged: (v) => context.read<TripProvider>().setSearchQuery(v),
                decoration: InputDecoration(
                  hintText: 'Rechercher un voyage...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 12),
            _StatusFilterDropdown(
              value: provider.statusFilter,
              onChanged: (v) => context.read<TripProvider>().setStatusFilter(v),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Chips statistiques
        _StatsRow(provider: provider),
        const SizedBox(height: 24),

        // Contenu principal
        if (provider.listState == TripLoadState.loading)
          const Center(child: CircularProgressIndicator())
        else if (provider.listState == TripLoadState.error)
          _ErrorBanner(message: provider.listError ?? 'Erreur de chargement')
        else if (provider.filteredTrips.isEmpty)
          _EmptyState(
            hasFilter: provider.searchQuery.isNotEmpty || provider.statusFilter != 'ALL',
            isAdmin: isAdmin,
          )
        else
          _TripGrid(
            trips: provider.filteredTrips,
            isAdmin: isAdmin,
            selectedForExport: provider.selectedForExport,
          ),
      ],
    );
  }

  Future<void> _openCreateDialog(BuildContext context) async {
    context.read<TripProvider>().resetOpState();
    await TripFormDialog.show(context);
  }

  Future<void> _downloadBulkExport(BuildContext context) async {
    final provider = context.read<TripProvider>();
    final url = provider.getBulkExportUrl();
    _downloadFile(url);
  }

  void _downloadFile(String url) {
    final token = ApiClient.authToken;
    http.get(Uri.parse(url), headers: {
      if (token != null) 'Authorization': 'Bearer $token',
    }).then((response) {
      final blob = html.Blob([response.bodyBytes]);
      final blobUrl = html.Url.createObjectUrlFromBlob(blob);
      // Extraire le nom du fichier depuis Content-Disposition
      final disposition = response.headers['content-disposition'] ?? '';
      final match = RegExp(r'filename=(.+)').firstMatch(disposition);
      final filename = match?.group(1) ?? 'export.zip';
      html.AnchorElement(href: blobUrl)
        ..setAttribute('download', filename)
        ..click();
      html.Url.revokeObjectUrl(blobUrl);
    });
  }
}

/// Grille 2 colonnes des cartes voyages
class _TripGrid extends StatelessWidget {
  final List<Trip> trips;
  final bool isAdmin;
  final Set<String> selectedForExport;

  const _TripGrid({
    required this.trips,
    required this.isAdmin,
    required this.selectedForExport,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 600 ? 2 : 1;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 1.8,
          ),
          itemCount: trips.length,
          itemBuilder: (context, index) {
            final trip = trips[index];
            return TripCard(
              trip: trip,
              onEdit: isAdmin ? () => _openEditDialog(context, trip) : null,
              onDelete: isAdmin ? () => _confirmDelete(context, trip) : null,
              onExport: isAdmin ? () => _exportSingle(context, trip) : null,
              onViewTimeline: isAdmin ? () => context.go('/trips/${trip.id}/checkpoints') : null,
              isSelectedForExport: selectedForExport.contains(trip.id),
              onToggleExportSelection: isAdmin
                  ? () => context.read<TripProvider>().toggleExportSelection(trip.id)
                  : null,
            );
          },
        );
      },
    );
  }

  void _exportSingle(BuildContext context, Trip trip) {
    final url = context.read<TripProvider>().getSingleExportUrl(trip.id);
    final token = ApiClient.authToken;
    http.get(Uri.parse(url), headers: {
      if (token != null) 'Authorization': 'Bearer $token',
    }).then((response) {
      final blob = html.Blob([response.bodyBytes]);
      final blobUrl = html.Url.createObjectUrlFromBlob(blob);
      final disposition = response.headers['content-disposition'] ?? '';
      final match = RegExp(r'filename=(.+)').firstMatch(disposition);
      final filename = match?.group(1) ?? 'export.csv';
      html.AnchorElement(href: blobUrl)
        ..setAttribute('download', filename)
        ..click();
      html.Url.revokeObjectUrl(blobUrl);
    });
  }

  Future<void> _openEditDialog(BuildContext context, Trip trip) async {
    context.read<TripProvider>().resetOpState();
    await TripFormDialog.show(context, trip: trip);
  }

  Future<void> _confirmDelete(BuildContext context, Trip trip) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Supprimer le voyage ?'),
        content: Text(
          'Le voyage "${trip.destination}" sera définitivement supprimé. Cette action est irréversible.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      final success = await context.read<TripProvider>().deleteTrip(trip.id);
      if (!success && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.read<TripProvider>().opError ?? 'Erreur lors de la suppression.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

/// Ligne de chips statistiques (Actifs / À venir / Terminés / Total élèves)
class _StatsRow extends StatelessWidget {
  final TripProvider provider;

  const _StatsRow({required this.provider});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _StatCard(label: 'Voyages actifs', value: provider.activeCount, color: Colors.green.shade600)),
        const SizedBox(width: 12),
        Expanded(child: _StatCard(label: 'À venir', value: provider.plannedCount, color: Colors.blue.shade600)),
        const SizedBox(width: 12),
        Expanded(child: _StatCard(label: 'Terminés', value: provider.completedCount, color: Colors.grey.shade600)),
        const SizedBox(width: 12),
        Expanded(child: _StatCard(label: 'Total élèves', value: provider.totalStudents, color: Colors.indigo.shade600)),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final int value;
  final Color color;

  const _StatCard({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          const SizedBox(height: 4),
          Text(
            value.toString(),
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }
}

/// Dropdown filtre statut
class _StatusFilterDropdown extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _StatusFilterDropdown({required this.value, required this.onChanged});

  static const _options = [
    ('ALL', 'Tous les statuts'),
    ('PLANNED', 'À venir'),
    ('ACTIVE', 'En cours'),
    ('COMPLETED', 'Terminés'),
    ('ARCHIVED', 'Archivés'),
  ];

  @override
  Widget build(BuildContext context) {
    return DropdownButtonHideUnderline(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade400),
          borderRadius: BorderRadius.circular(8),
        ),
        child: DropdownButton<String>(
          value: value,
          items: _options
              .map((o) => DropdownMenuItem(value: o.$1, child: Text(o.$2)))
              .toList(),
          onChanged: (v) => onChanged(v!),
        ),
      ),
    );
  }
}

/// Bannière d'erreur
class _ErrorBanner extends StatelessWidget {
  final String message;

  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: Colors.red.shade700),
          const SizedBox(width: 12),
          Expanded(child: Text(message, style: TextStyle(color: Colors.red.shade800))),
          TextButton(
            onPressed: () => context.read<TripProvider>().loadTrips(),
            child: const Text('Réessayer'),
          ),
        ],
      ),
    );
  }
}

/// État vide (aucun voyage ou aucun résultat)
class _EmptyState extends StatelessWidget {
  final bool hasFilter;
  final bool isAdmin;

  const _EmptyState({required this.hasFilter, required this.isAdmin});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        children: [
          const SizedBox(height: 40),
          Icon(Icons.directions_bus_outlined, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            hasFilter ? 'Aucun voyage ne correspond à la recherche.' : 'Aucun voyage pour l\'instant.',
            style: TextStyle(color: Colors.grey.shade600),
          ),
          if (!hasFilter && isAdmin) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () {
                context.read<TripProvider>().resetOpState();
                TripFormDialog.show(context);
              },
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Créer le premier voyage'),
            ),
          ],
        ],
      ),
    );
  }
}
