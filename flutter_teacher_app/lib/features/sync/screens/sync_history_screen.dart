/// Ecran d'historique des synchronisations (US 3.1 — critere #6).
///
/// Affiche la liste des synchronisations passees avec date, nombre de
/// presences envoyees/acceptees/echouees et statut.
library;

import 'package:flutter/material.dart';
import '../../../core/database/local_db.dart';

class SyncHistoryScreen extends StatefulWidget {
  const SyncHistoryScreen({super.key});

  @override
  State<SyncHistoryScreen> createState() => _SyncHistoryScreenState();
}

class _SyncHistoryScreenState extends State<SyncHistoryScreen> {
  late Future<List<SyncHistoryEntry>> _historyFuture;

  @override
  void initState() {
    super.initState();
    _historyFuture = LocalDb.instance.getSyncHistory();
  }

  void _refresh() {
    setState(() {
      _historyFuture = LocalDb.instance.getSyncHistory();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Historique des synchronisations'),
        backgroundColor: const Color(0xFF1A73E8),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Rafraichir',
            onPressed: _refresh,
          ),
        ],
      ),
      body: FutureBuilder<List<SyncHistoryEntry>>(
        future: _historyFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Text('Erreur : ${snapshot.error}'),
            );
          }

          final entries = snapshot.data!;
          if (entries.isEmpty) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.sync_disabled, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'Aucune synchronisation effectuee',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: entries.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) => _SyncHistoryCard(entry: entries[index]),
          );
        },
      ),
    );
  }
}

// ----------------------------------------------------------------
// Carte d'une entree d'historique
// ----------------------------------------------------------------

class _SyncHistoryCard extends StatelessWidget {
  final SyncHistoryEntry entry;

  const _SyncHistoryCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    final (icon, color, label) = _statusInfo(entry.status);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // En-tete : date + statut
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                const Spacer(),
                Text(
                  _formatDate(entry.syncedAt),
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Statistiques
            Row(
              children: [
                _StatChip(
                  label: 'Envoyees',
                  value: entry.recordsSent,
                  color: Colors.blue,
                ),
                const SizedBox(width: 8),
                _StatChip(
                  label: 'Acceptees',
                  value: entry.recordsAccepted,
                  color: Colors.green,
                ),
                if (entry.recordsDuplicate > 0) ...[
                  const SizedBox(width: 8),
                  _StatChip(
                    label: 'Doublons',
                    value: entry.recordsDuplicate,
                    color: Colors.orange,
                  ),
                ],
                if (entry.recordsFailed > 0) ...[
                  const SizedBox(width: 8),
                  _StatChip(
                    label: 'Echouees',
                    value: entry.recordsFailed,
                    color: Colors.red,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  (IconData, Color, String) _statusInfo(String status) {
    return switch (status) {
      'SUCCESS' => (Icons.check_circle, Colors.green, 'Succes'),
      'PARTIAL' => (Icons.warning_amber, Colors.orange, 'Partiel'),
      'OFFLINE' => (Icons.cloud_off, Colors.grey, 'Hors ligne'),
      _ => (Icons.error_outline, Colors.red, status),
    };
  }

  String _formatDate(DateTime dt) {
    final d = dt.toLocal();
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
}

// ----------------------------------------------------------------
// Chip de statistique
// ----------------------------------------------------------------

class _StatChip extends StatelessWidget {
  final String label;
  final int value;
  final Color color;

  const _StatChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Text(
        '$value $label',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
