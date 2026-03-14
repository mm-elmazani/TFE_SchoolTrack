import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/checkpoint_timeline_provider.dart';

/// Ecran US 4.4 — Timeline et resume des checkpoints d'un voyage.
/// Accessible depuis le detail ou la carte d'un voyage (direction uniquement).
class CheckpointTimelineScreen extends StatefulWidget {
  final String tripId;

  const CheckpointTimelineScreen({super.key, required this.tripId});

  @override
  State<CheckpointTimelineScreen> createState() =>
      _CheckpointTimelineScreenState();
}

class _CheckpointTimelineScreenState extends State<CheckpointTimelineScreen> {
  late final CheckpointTimelineProvider _provider;

  @override
  void initState() {
    super.initState();
    _provider = CheckpointTimelineProvider();
    _provider.loadSummary(widget.tripId);
  }

  @override
  void dispose() {
    _provider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _provider,
      child: Consumer<CheckpointTimelineProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (provider.error != null) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline, size: 48,
                      color: Colors.red.shade300),
                  const SizedBox(height: 8),
                  Text(provider.error!,
                      style: TextStyle(color: Colors.red.shade700)),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: () => provider.loadSummary(widget.tripId),
                    child: const Text('Reessayer'),
                  ),
                ],
              ),
            );
          }

          final summary = provider.summary;
          if (summary == null) {
            return const Center(child: Text('Aucune donnee.'));
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Stats globales
                _SummaryCards(summary: summary),
                const SizedBox(height: 24),

                // Timeline
                Text(
                  'Timeline des checkpoints',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),

                if (summary.timeline.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        'Aucun checkpoint pour ce voyage.',
                        style: TextStyle(color: Colors.grey.shade500),
                      ),
                    ),
                  )
                else
                  ...summary.timeline.map((entry) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _TimelineCard(
                          entry: entry,
                          isLast: entry == summary.timeline.last,
                        ),
                      )),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Stats cards
// ---------------------------------------------------------------------------

class _SummaryCards extends StatelessWidget {
  final CheckpointsSummary summary;

  const _SummaryCards({required this.summary});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            label: 'Checkpoints',
            value: summary.totalCheckpoints.toString(),
            icon: Icons.flag,
            color: Colors.blue.shade600,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            label: 'Actifs',
            value: summary.activeCheckpoints.toString(),
            icon: Icons.play_circle,
            color: Colors.green.shade600,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            label: 'Clotures',
            value: summary.closedCheckpoints.toString(),
            icon: Icons.check_circle,
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            label: 'Scans totaux',
            value: summary.totalScans.toString(),
            icon: Icons.qr_code_scanner,
            color: Colors.purple.shade600,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            label: 'Duree moy.',
            value: summary.avgDurationMinutes != null
                ? '${summary.avgDurationMinutes!.toStringAsFixed(0)} min'
                : '-',
            icon: Icons.timer,
            color: Colors.orange.shade600,
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style:
                      TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold, color: color),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Timeline card
// ---------------------------------------------------------------------------

class _TimelineCard extends StatelessWidget {
  final CheckpointTimelineEntry entry;
  final bool isLast;

  const _TimelineCard({required this.entry, this.isLast = false});

  @override
  Widget build(BuildContext context) {
    final statusInfo = _statusInfo(entry.status);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline indicator
          SizedBox(
            width: 40,
            child: Column(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: statusInfo.$2,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      entry.sequenceOrder.toString(),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: statusInfo.$1,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: Colors.grey.shade300,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),

          // Card
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.only(bottom: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header : nom + status badge
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          entry.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 15),
                        ),
                      ),
                      _StatusBadge(
                          label: statusInfo.$3, color: statusInfo.$1),
                    ],
                  ),

                  if (entry.description != null &&
                      entry.description!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      entry.description!,
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ],

                  const SizedBox(height: 12),

                  // Stats row
                  Wrap(
                    spacing: 20,
                    runSpacing: 8,
                    children: [
                      _InfoChip(
                        icon: Icons.qr_code_scanner,
                        label: '${entry.scanCount} scans',
                      ),
                      _InfoChip(
                        icon: Icons.people,
                        label: '${entry.studentCount} eleves',
                      ),
                      if (entry.durationMinutes != null)
                        _InfoChip(
                          icon: Icons.timer,
                          label: '${entry.durationMinutes} min',
                        ),
                      if (entry.createdByName != null)
                        _InfoChip(
                          icon: Icons.person,
                          label: entry.createdByName!,
                        ),
                    ],
                  ),

                  // Timestamps
                  if (entry.startedAt != null || entry.closedAt != null) ...[
                    const SizedBox(height: 8),
                    const Divider(height: 1),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 16,
                      runSpacing: 4,
                      children: [
                        if (entry.startedAt != null)
                          Text(
                            'Debut : ${_formatTime(entry.startedAt!)}',
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey.shade500),
                          ),
                        if (entry.closedAt != null)
                          Text(
                            'Fin : ${_formatTime(entry.closedAt!)}',
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey.shade500),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  (Color, Color, String) _statusInfo(String status) {
    return switch (status) {
      'ACTIVE' => (Colors.green.shade700, Colors.green.shade50, 'Actif'),
      'CLOSED' => (Colors.grey.shade600, Colors.grey.shade100, 'Cloture'),
      'DRAFT' => (Colors.blue.shade600, Colors.blue.shade50, 'Brouillon'),
      _ => (Colors.grey, Colors.grey.shade100, status),
    };
  }

  String _formatTime(String isoDate) {
    try {
      final dt = DateTime.parse(isoDate);
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} '
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return isoDate;
    }
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600, color: color)),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.grey.shade500),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
      ],
    );
  }
}
