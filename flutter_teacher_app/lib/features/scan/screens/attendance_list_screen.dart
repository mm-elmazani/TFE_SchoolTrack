/// Écran de suivi temps réel des présences (US 2.3 + US 2.4).
///
/// Affiche deux sections : élèves présents et élèves manquants.
/// Se met à jour en temps réel via Consumer de ScanProvider à chaque scan.
/// Appui long sur un élève manquant → dialog de marquage manuel (US 2.4).
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/scan_provider.dart';
import '../../../features/trips/models/offline_bundle.dart';

/// Reçoit le ScanProvider depuis ScanScreen via GoRouter extra.
class AttendanceListScreen extends StatelessWidget {
  final ScanProvider provider;
  final String checkpointName;
  final String tripDestination;

  const AttendanceListScreen({
    super.key,
    required this.provider,
    required this.checkpointName,
    required this.tripDestination,
  });

  /// Ouvre le dialog de marquage manuel pour [student] (US 2.4).
  void _showManualMarkDialog(
    BuildContext context,
    ScanProvider provider,
    OfflineStudent student,
  ) {
    showDialog<void>(
      context: context,
      builder: (_) => _ManualMarkDialog(
        student: student,
        onConfirm: (justification, comment) => provider.markManually(
          student: student,
          justification: justification,
          comment: comment,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Partage l'instance existante — pas de nouveau provider
    return ChangeNotifierProvider.value(
      value: provider,
      child: Consumer<ScanProvider>(
        builder: (context, p, _) {
          final present = p.presentStudents;
          final missing = p.missingStudents;

          return Scaffold(
            appBar: AppBar(
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(checkpointName),
                  Text(
                    tripDestination,
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
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Center(
                    child: Text(
                      '${p.presentCount} / ${p.totalStudents}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            body: CustomScrollView(
              slivers: [
                // ------------------------------------------------
                // Section Présents
                // ------------------------------------------------
                _SectionHeader(
                  label: 'Présents',
                  count: present.length,
                  color: Colors.green.shade700,
                  icon: Icons.check_circle,
                ),
                if (present.isEmpty)
                  const SliverToBoxAdapter(
                    child: _EmptyHint(
                      message: 'Aucun élève scanné pour l\'instant.',
                    ),
                  )
                else
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => _PresentTile(
                        student: present[i],
                        info: p.scanInfoOf(present[i].id)!,
                      ),
                      childCount: present.length,
                    ),
                  ),

                // ------------------------------------------------
                // Section Manquants
                // ------------------------------------------------
                _SectionHeader(
                  label: 'Manquants',
                  count: missing.length,
                  color: missing.isEmpty
                      ? Colors.green.shade700
                      : Colors.orange.shade800,
                  icon: missing.isEmpty
                      ? Icons.check_circle
                      : Icons.warning_amber_rounded,
                ),
                if (missing.isEmpty)
                  const SliverToBoxAdapter(
                    child: _EmptyHint(
                      message: 'Tous les élèves sont présents !',
                    ),
                  )
                else
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => _MissingTile(
                        student: missing[i],
                        onLongPress: () => _showManualMarkDialog(
                          context,
                          p,
                          missing[i],
                        ),
                      ),
                      childCount: missing.length,
                    ),
                  ),

                // Espace en bas pour le scroll
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ----------------------------------------------------------------
// En-tête de section
// ----------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  final IconData icon;

  const _SectionHeader({
    required this.label,
    required this.count,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Container(
        color: color.withAlpha(20),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Text(
              '$label ($count)',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------
// Ligne — élève présent
// ----------------------------------------------------------------

class _PresentTile extends StatelessWidget {
  final OfflineStudent student;
  final StudentScanInfo info;

  const _PresentTile({required this.student, required this.info});

  @override
  Widget build(BuildContext context) {
    final timeLabel =
        '${info.scannedAt.hour.toString().padLeft(2, '0')}:${info.scannedAt.minute.toString().padLeft(2, '0')}';

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Colors.green.shade100,
        child: Icon(Icons.check, color: Colors.green.shade700, size: 20),
      ),
      title: Text(
        student.fullName,
        style: const TextStyle(fontWeight: FontWeight.w500),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ScanBadge(method: info.scanMethod),
          const SizedBox(width: 8),
          Text(
            timeLabel,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey,
                ),
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------
// Ligne — élève manquant (US 2.3 + US 2.4 : appui long)
// ----------------------------------------------------------------

class _MissingTile extends StatelessWidget {
  final OfflineStudent student;
  final VoidCallback onLongPress;

  const _MissingTile({
    required this.student,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onLongPress: onLongPress,
      leading: CircleAvatar(
        backgroundColor: Colors.grey.shade100,
        child: Icon(Icons.person_outline, color: Colors.grey.shade400),
      ),
      title: Text(
        student.fullName,
        style: TextStyle(color: Colors.grey.shade600),
      ),
      trailing: Tooltip(
        message: 'Appui long pour marquer manuellement',
        child: Icon(
          Icons.touch_app_outlined,
          size: 16,
          color: Colors.grey.shade400,
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------
// Badge méthode de scan
// ----------------------------------------------------------------

class _ScanBadge extends StatelessWidget {
  final String method;

  const _ScanBadge({required this.method});

  @override
  Widget build(BuildContext context) {
    final (emoji, label) = switch (method) {
      'NFC_PHYSICAL' => ('📲', 'NFC'),
      'QR_PHYSICAL' => ('📷', 'QR'),
      'QR_DIGITAL' => ('📧', 'Email'),
      _ => ('👤', 'Manuel'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Text('$emoji $label', style: const TextStyle(fontSize: 11)),
    );
  }
}

// ----------------------------------------------------------------
// Message section vide
// ----------------------------------------------------------------

class _EmptyHint extends StatelessWidget {
  final String message;

  const _EmptyHint({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Text(
        message,
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: Colors.grey),
      ),
    );
  }
}

// ----------------------------------------------------------------
// Dialog de marquage manuel (US 2.4)
// ----------------------------------------------------------------

class _ManualMarkDialog extends StatefulWidget {
  final OfflineStudent student;
  final Future<void> Function(String justification, String? comment) onConfirm;

  const _ManualMarkDialog({
    required this.student,
    required this.onConfirm,
  });

  @override
  State<_ManualMarkDialog> createState() => _ManualMarkDialogState();
}

class _ManualMarkDialogState extends State<_ManualMarkDialog> {
  String _selectedJustification =
      ScanProvider.justificationOptions.first.$1;
  final _commentController = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    setState(() => _loading = true);
    await widget.onConfirm(
      _selectedJustification,
      _commentController.text.trim().isEmpty
          ? null
          : _commentController.text.trim(),
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Marquage manuel'),
          Text(
            widget.student.fullName,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Justification',
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(color: Colors.grey.shade600),
          ),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            initialValue: _selectedJustification,
            isExpanded: true,
            items: ScanProvider.justificationOptions
                .map((e) => DropdownMenuItem(
                      value: e.$1,
                      child: Text(e.$2),
                    ))
                .toList(),
            onChanged: _loading
                ? null
                : (v) => setState(() => _selectedJustification = v!),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _commentController,
            enabled: !_loading,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Commentaire (optionnel)',
              border: OutlineInputBorder(),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton.icon(
          onPressed: _loading ? null : _confirm,
          icon: _loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check, size: 18),
          label: const Text('Confirmer'),
        ),
      ],
    );
  }
}
