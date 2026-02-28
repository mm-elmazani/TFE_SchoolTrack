/// Écran de sélection d'un checkpoint avant de démarrer le scan (US 2.2 + US 2.5).
///
/// L'enseignant sélectionne un checkpoint existant ou en crée un nouveau (bouton +).
/// Le checkpoint créé est d'abord sauvegardé localement en SQLite (DRAFT),
/// puis une tentative de création sur le backend est faite en best-effort.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/api/api_client.dart';
import '../../../core/database/local_db.dart';
import '../../../features/trips/models/offline_bundle.dart';

/// Écran listant les checkpoints d'un voyage pour en sélectionner un.
class CheckpointSelectionScreen extends StatefulWidget {
  final String tripId;
  final String tripDestination;

  const CheckpointSelectionScreen({
    super.key,
    required this.tripId,
    required this.tripDestination,
  });

  @override
  State<CheckpointSelectionScreen> createState() =>
      _CheckpointSelectionScreenState();
}

class _CheckpointSelectionScreenState
    extends State<CheckpointSelectionScreen> {
  List<OfflineCheckpoint>? _checkpoints;
  String? _error;
  final _apiClient = ApiClient();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final cps = await LocalDb.instance.getCheckpoints(widget.tripId);
      if (mounted) setState(() => _checkpoints = cps);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  /// Ouvre le dialog de création d'un checkpoint (US 2.5).
  Future<void> _showCreateDialog() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _CreateCheckpointDialog(),
    );
    if (name == null || name.isEmpty) return;

    // 1. Créer localement en SQLite (offline-first)
    final created = await LocalDb.instance.createCheckpoint(
      tripId: widget.tripId,
      name: name,
    );

    // 2. Tenter la création sur le backend (best-effort)
    _apiClient.createCheckpoint(widget.tripId, name);

    // 3. Rafraîchir la liste et sélectionner directement le nouveau checkpoint
    await _load();
    if (mounted) _onCheckpointSelected(created);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateDialog,
        icon: const Icon(Icons.add_location_alt_outlined),
        label: const Text('Nouveau checkpoint'),
      ),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Sélectionner un checkpoint'),
            Text(
              widget.tripDestination,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onPrimary
                        .withAlpha(200),
                  ),
            ),
          ],
        ),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: _load, child: const Text('Réessayer')),
            ],
          ),
        ),
      );
    }

    if (_checkpoints == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_checkpoints!.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: _EmptyCheckpoints(),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _checkpoints!.length,
        separatorBuilder: (context, index) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          final cp = _checkpoints![i];
          return _CheckpointCard(
            checkpoint: cp,
            onTap: () => _onCheckpointSelected(cp),
          );
        },
      ),
    );
  }

  void _onCheckpointSelected(OfflineCheckpoint checkpoint) {
    if (checkpoint.status == 'CLOSED') {
      // Un checkpoint clôturé ne peut pas être utilisé pour scanner
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ce checkpoint est clôturé. Sélectionnez-en un autre.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    context.push(
      '/scan',
      extra: {
        'tripId': widget.tripId,
        'tripDestination': widget.tripDestination,
        'checkpointId': checkpoint.id,
        'checkpointName': checkpoint.name,
      },
    );
  }
}

// ----------------------------------------------------------------
// Carte checkpoint
// ----------------------------------------------------------------

class _CheckpointCard extends StatelessWidget {
  final OfflineCheckpoint checkpoint;
  final VoidCallback onTap;

  const _CheckpointCard({required this.checkpoint, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isClosed = checkpoint.status == 'CLOSED';
    final color = Theme.of(context).colorScheme;

    return Card(
      child: InkWell(
        onTap: isClosed ? null : onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Numéro de séquence
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isClosed
                      ? Colors.grey.shade200
                      : color.primaryContainer,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  '${checkpoint.sequenceOrder}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isClosed ? Colors.grey : color.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // Nom + badge statut
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      checkpoint.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: isClosed ? Colors.grey : null,
                          ),
                    ),
                    const SizedBox(height: 4),
                    _StatusBadge(status: checkpoint.status),
                  ],
                ),
              ),
              // Flèche si disponible
              if (!isClosed)
                Icon(Icons.chevron_right, color: color.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------
// Badge statut checkpoint
// ----------------------------------------------------------------

class _StatusBadge extends StatelessWidget {
  final String status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'ACTIVE' => ('ACTIF', Colors.green),
      'DRAFT' => ('BROUILLON', Colors.blue),
      'CLOSED' => ('CLÔTURÉ', Colors.grey),
      _ => (status, Colors.grey),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        border: Border.all(color: color.withAlpha(80)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color.shade700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------
// Vue vide
// ----------------------------------------------------------------

class _EmptyCheckpoints extends StatelessWidget {
  const _EmptyCheckpoints();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.add_location_alt_outlined,
            size: 56, color: Colors.grey.shade400),
        const SizedBox(height: 16),
        Text(
          'Aucun checkpoint disponible',
          style: Theme.of(context).textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Appuyez sur "+ Nouveau checkpoint" pour en créer un.',
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: Colors.grey.shade600),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

// ----------------------------------------------------------------
// Dialog de création d'un checkpoint (US 2.5)
// ----------------------------------------------------------------

class _CreateCheckpointDialog extends StatefulWidget {
  const _CreateCheckpointDialog();

  @override
  State<_CreateCheckpointDialog> createState() =>
      _CreateCheckpointDialogState();
}

class _CreateCheckpointDialogState extends State<_CreateCheckpointDialog> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nouveau checkpoint'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Nom du checkpoint',
            hintText: 'ex : Arrêt bus, Entrée musée…',
            border: OutlineInputBorder(),
          ),
          textCapitalization: TextCapitalization.sentences,
          validator: (v) =>
              (v == null || v.trim().isEmpty) ? 'Nom obligatoire' : null,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.of(context).pop(_controller.text.trim());
            }
          },
          child: const Text('Créer'),
        ),
      ],
    );
  }
}
