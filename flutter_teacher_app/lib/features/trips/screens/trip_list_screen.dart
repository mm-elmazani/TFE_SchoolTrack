/// Écran principal US 2.1 — Liste des voyages avec téléchargement offline.
///
/// Fonctionnalités :
///   - Affiche les voyages disponibles (depuis l'API)
///   - Bouton "Télécharger" par voyage
///   - Badge "✓ Prêt hors-ligne" si téléchargé et valide (< 7 jours)
///   - Indicateur de chargement pendant le téléchargement
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/trip_provider.dart';
import '../models/offline_bundle.dart';

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

// ----------------------------------------------------------------
// Corps principal
// ----------------------------------------------------------------

class _TripListBody extends StatelessWidget {
  const _TripListBody();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TripProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('SchoolTrack'),
        backgroundColor: const Color(0xFF1A73E8),
        foregroundColor: Colors.white,
        actions: [
          // Bouton rafraîchir
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Rafraîchir',
            onPressed: provider.listState == TripListState.loading
                ? null
                : () => context.read<TripProvider>().loadTrips(),
          ),
        ],
      ),
      body: switch (provider.listState) {
        TripListState.loading => const _LoadingView(),
        TripListState.error =>
          _ErrorView(message: provider.listError ?? 'Erreur inconnue'),
        _ => provider.trips.isEmpty
            ? const _EmptyView()
            : _TripList(trips: provider.trips),
      },
    );
  }
}

// ----------------------------------------------------------------
// Liste des voyages
// ----------------------------------------------------------------

class _TripList extends StatelessWidget {
  final List<TripSummary> trips;

  const _TripList({required this.trips});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: trips.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) => _TripCard(trip: trips[index]),
    );
  }
}

// ----------------------------------------------------------------
// Carte d'un voyage
// ----------------------------------------------------------------

class _TripCard extends StatelessWidget {
  final TripSummary trip;

  const _TripCard({required this.trip});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TripProvider>();
    final state = provider.downloadStateOf(trip.id);
    final isReady = provider.isReady(trip.id);
    final downloadedAt = provider.downloadedAtOf(trip.id);
    final error = provider.downloadErrorOf(trip.id);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // En-tête : destination + statut
            Row(
              children: [
                Expanded(
                  child: Text(
                    trip.destination,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                _StatusBadge(status: trip.status),
              ],
            ),
            const SizedBox(height: 6),

            // Date + nombre d'élèves
            Row(
              children: [
                const Icon(Icons.calendar_today,
                    size: 14, color: Colors.grey),
                const SizedBox(width: 4),
                Text(
                  trip.date,
                  style: TextStyle(color: Colors.grey.shade600),
                ),
                const SizedBox(width: 16),
                const Icon(Icons.people, size: 14, color: Colors.grey),
                const SizedBox(width: 4),
                Text(
                  '${trip.studentCount} élèves',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Badge "Prêt hors-ligne" + date de téléchargement
            if (isReady && downloadedAt != null) ...[
              _OfflineReadyBadge(downloadedAt: downloadedAt),
              const SizedBox(height: 12),
            ],

            // Message d'erreur de téléchargement
            if (error != null) ...[
              _ErrorBanner(message: error),
              const SizedBox(height: 12),
            ],

            // Bouton téléchargement
            _DownloadButton(
              trip: trip,
              state: state,
              isReady: isReady,
            ),

            // Bouton scanner — visible uniquement si le voyage est prêt hors-ligne
            if (isReady) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0F9D58),
                  ),
                  onPressed: () => context.push(
                    '/checkpoints',
                    extra: {
                      'tripId': trip.id,
                      'tripDestination': trip.destination,
                    },
                  ),
                  icon: const Icon(Icons.qr_code_scanner, size: 18),
                  label: const Text('Scanner les présences'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------
// Bouton de téléchargement
// ----------------------------------------------------------------

class _DownloadButton extends StatelessWidget {
  final TripSummary trip;
  final DownloadState state;
  final bool isReady;

  const _DownloadButton({
    required this.trip,
    required this.state,
    required this.isReady,
  });

  @override
  Widget build(BuildContext context) {
    if (state == DownloadState.downloading) {
      return const Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 10),
          Text('Téléchargement en cours...'),
        ],
      );
    }

    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor:
              isReady ? Colors.green.shade600 : const Color(0xFF1A73E8),
        ),
        onPressed: () =>
            context.read<TripProvider>().downloadBundle(trip.id),
        icon: Icon(isReady ? Icons.refresh : Icons.download, size: 18),
        label: Text(
          isReady ? 'Mettre à jour les données' : 'Télécharger pour hors-ligne',
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------
// Widgets auxiliaires
// ----------------------------------------------------------------

/// Badge coloré affichant le statut du voyage.
class _StatusBadge extends StatelessWidget {
  final String status;

  const _StatusBadge({required this.status});

  static const _config = {
    'PLANNED': ('Planifié', Color(0xFF1565C0)),
    'ACTIVE': ('En cours', Color(0xFF2E7D32)),
    'COMPLETED': ('Terminé', Color(0xFF616161)),
    'ARCHIVED': ('Archivé', Color(0xFF9E9E9E)),
  };

  @override
  Widget build(BuildContext context) {
    final info = _config[status];
    final label = info?.$1 ?? status;
    final color = info?.$2 ?? Colors.grey;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

/// Badge vert "✓ Prêt hors-ligne" avec date de téléchargement.
class _OfflineReadyBadge extends StatelessWidget {
  final DateTime downloadedAt;

  const _OfflineReadyBadge({required this.downloadedAt});

  @override
  Widget build(BuildContext context) {
    final formatted =
        '${downloadedAt.day.toString().padLeft(2, '0')}/'
        '${downloadedAt.month.toString().padLeft(2, '0')}/'
        '${downloadedAt.year} '
        '${downloadedAt.hour.toString().padLeft(2, '0')}:'
        '${downloadedAt.minute.toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle, size: 16, color: Colors.green.shade700),
          const SizedBox(width: 6),
          Text(
            '✓ Prêt hors-ligne — téléchargé le $formatted',
            style: TextStyle(
              fontSize: 12,
              color: Colors.green.shade800,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// Bannière d'erreur de téléchargement.
class _ErrorBanner extends StatelessWidget {
  final String message;

  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 16, color: Colors.red.shade700),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 12, color: Colors.red.shade800),
            ),
          ),
        ],
      ),
    );
  }
}

/// Vue chargement.
class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 12),
          Text('Chargement des voyages...'),
        ],
      ),
    );
  }
}

/// Vue aucun voyage.
class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.directions_bus_outlined,
              size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(
            'Aucun voyage disponible.',
            style: TextStyle(color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }
}

/// Vue erreur de chargement.
class _ErrorView extends StatelessWidget {
  final String message;

  const _ErrorView({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off, size: 56, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => context.read<TripProvider>().loadTrips(),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Réessayer'),
            ),
          ],
        ),
      ),
    );
  }
}
