import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/alert_provider.dart';

/// Ecran US 4.3 — Alertes temps reel pour la direction.
/// Affiche les alertes actives avec workflow de resolution.
/// Polling automatique toutes les 30 secondes.
class AlertScreen extends StatefulWidget {
  const AlertScreen({super.key});

  @override
  State<AlertScreen> createState() => _AlertScreenState();
}

class _AlertScreenState extends State<AlertScreen> {
  late final AlertProvider _provider;

  @override
  void initState() {
    super.initState();
    _provider = AlertProvider();
    _provider.loadAlerts();
    _provider.startPolling();
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
      child: Consumer<AlertProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                _Header(provider: provider),
                const SizedBox(height: 20),

                // Stats
                _StatsRow(stats: provider.stats),
                const SizedBox(height: 24),

                // Liste des alertes
                if (provider.error != null)
                  _ErrorBanner(message: provider.error!)
                else if (provider.alerts.isEmpty)
                  _EmptyState(filter: provider.statusFilter)
                else
                  ...provider.alerts.map((alert) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _AlertCard(
                          alert: alert,
                          onAcknowledge: () => provider.updateStatus(alert.id, 'IN_PROGRESS'),
                          onResolve: () => provider.updateStatus(alert.id, 'RESOLVED'),
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
// Header
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  final AlertProvider provider;

  const _Header({required this.provider});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Text(
                'Suivi des alertes en temps reel (rafraichissement 30s)',
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
        _FilterDropdown(
          value: provider.statusFilter,
          onChanged: provider.setStatusFilter,
        ),
        const SizedBox(width: 12),
        IconButton(
          onPressed: provider.loadAlerts,
          icon: const Icon(Icons.refresh, size: 20),
          tooltip: 'Rafraichir',
        ),
      ],
    );
  }
}

class _FilterDropdown extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _FilterDropdown({required this.value, required this.onChanged});

  static const _options = [
    ('ACTIVE', 'Actives'),
    ('IN_PROGRESS', 'En cours'),
    ('RESOLVED', 'Resolues'),
    ('ALL', 'Toutes'),
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

// ---------------------------------------------------------------------------
// Stats row
// ---------------------------------------------------------------------------

class _StatsRow extends StatelessWidget {
  final AlertStats stats;

  const _StatsRow({required this.stats});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _StatCard(
          label: 'Actives',
          value: stats.active,
          color: Colors.red.shade600,
          icon: Icons.warning_amber,
        )),
        const SizedBox(width: 12),
        Expanded(child: _StatCard(
          label: 'En cours',
          value: stats.inProgress,
          color: Colors.orange.shade600,
          icon: Icons.pending,
        )),
        const SizedBox(width: 12),
        Expanded(child: _StatCard(
          label: 'Resolues',
          value: stats.resolved,
          color: Colors.green.shade600,
          icon: Icons.check_circle,
        )),
        const SizedBox(width: 12),
        Expanded(child: _StatCard(
          label: 'Critiques',
          value: stats.critical,
          color: Colors.red.shade900,
          icon: Icons.error,
        )),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  final IconData icon;

  const _StatCard({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
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
              Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              const SizedBox(height: 2),
              Text(
                value.toString(),
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Alert card
// ---------------------------------------------------------------------------

class _AlertCard extends StatelessWidget {
  final AlertData alert;
  final VoidCallback onAcknowledge;
  final VoidCallback onResolve;

  const _AlertCard({
    required this.alert,
    required this.onAcknowledge,
    required this.onResolve,
  });

  @override
  Widget build(BuildContext context) {
    final severityInfo = _severityInfo(alert.severity);
    final statusInfo = _statusInfo(alert.status);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: alert.severity == 'CRITICAL'
              ? Colors.red.shade300
              : Colors.grey.shade200,
          width: alert.severity == 'CRITICAL' ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // En-tete : type + severite + statut
          Row(
            children: [
              Icon(severityInfo.$2, color: severityInfo.$1, size: 20),
              const SizedBox(width: 8),
              Text(
                _alertTypeLabel(alert.alertType),
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: severityInfo.$1,
                ),
              ),
              const SizedBox(width: 12),
              _Badge(label: severityInfo.$3, color: severityInfo.$1),
              const SizedBox(width: 8),
              _Badge(label: statusInfo.$1, color: statusInfo.$2),
              const Spacer(),
              if (alert.createdAt != null)
                Text(
                  _formatTime(alert.createdAt!),
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // Details
          Row(
            children: [
              Icon(Icons.person, size: 14, color: Colors.grey.shade500),
              const SizedBox(width: 4),
              Text(alert.studentName ?? 'Inconnu', style: const TextStyle(fontSize: 13)),
              const SizedBox(width: 16),
              Icon(Icons.directions_bus, size: 14, color: Colors.grey.shade500),
              const SizedBox(width: 4),
              Text(alert.tripDestination ?? '', style: const TextStyle(fontSize: 13)),
              if (alert.checkpointName != null) ...[
                const SizedBox(width: 16),
                Icon(Icons.location_on, size: 14, color: Colors.grey.shade500),
                const SizedBox(width: 4),
                Text(alert.checkpointName!, style: const TextStyle(fontSize: 13)),
              ],
            ],
          ),

          if (alert.message != null && alert.message!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(alert.message!, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
          ],

          // Actions
          if (alert.status != 'RESOLVED') ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (alert.status == 'ACTIVE')
                  OutlinedButton.icon(
                    onPressed: onAcknowledge,
                    icon: const Icon(Icons.visibility, size: 16),
                    label: const Text('Prendre en charge'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.orange.shade700,
                    ),
                  ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: onResolve,
                  icon: const Icon(Icons.check, size: 16),
                  label: const Text('Resoudre'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.green.shade600,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _alertTypeLabel(String type) {
    return switch (type) {
      'STUDENT_MISSING' => 'Eleve manquant',
      'CHECKPOINT_DELAYED' => 'Checkpoint en retard',
      'SYNC_FAILED' => 'Echec synchronisation',
      _ => type,
    };
  }

  (Color, IconData, String) _severityInfo(String severity) {
    return switch (severity) {
      'CRITICAL' => (Colors.red.shade800, Icons.error, 'Critique'),
      'HIGH' => (Colors.red.shade600, Icons.warning_amber, 'Haute'),
      'MEDIUM' => (Colors.orange.shade600, Icons.info_outline, 'Moyenne'),
      'LOW' => (Colors.blue.shade600, Icons.info_outline, 'Basse'),
      _ => (Colors.grey, Icons.info_outline, severity),
    };
  }

  (String, Color) _statusInfo(String status) {
    return switch (status) {
      'ACTIVE' => ('Active', Colors.red.shade600),
      'IN_PROGRESS' => ('En cours', Colors.orange.shade600),
      'RESOLVED' => ('Resolue', Colors.green.shade600),
      _ => (status, Colors.grey),
    };
  }

  String _formatTime(String isoDate) {
    try {
      final dt = DateTime.parse(isoDate);
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return isoDate;
    }
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;

  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
    );
  }
}

// ---------------------------------------------------------------------------
// Error / Empty
// ---------------------------------------------------------------------------

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
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String filter;

  const _EmptyState({required this.filter});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        children: [
          const SizedBox(height: 40),
          Icon(Icons.check_circle_outline, size: 64, color: Colors.green.shade300),
          const SizedBox(height: 16),
          Text(
            filter == 'ACTIVE'
                ? 'Aucune alerte active. Tout est en ordre.'
                : 'Aucune alerte pour ce filtre.',
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}
