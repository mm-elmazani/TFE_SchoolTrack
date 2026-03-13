import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';

import '../models/dashboard_models.dart';
import '../providers/dashboard_provider.dart';

/// Ecran US 4.2 — Vue d'ensemble du dashboard direction.
/// Stats, taux presence, graphes par checkpoint, auto-refresh 60s.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late final DashboardProvider _provider;

  @override
  void initState() {
    super.initState();
    _provider = DashboardProvider();
    _provider.loadOverview();
    _provider.startAutoRefresh();
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
      child: Consumer<DashboardProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (provider.error != null && provider.overview == null) {
            return _ErrorState(
              message: provider.error!,
              onRetry: provider.loadOverview,
            );
          }

          final overview = provider.overview;
          if (overview == null) {
            return const Center(child: Text('Chargement...'));
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // En-tete + filtre + refresh
                _Header(provider: provider),
                const SizedBox(height: 24),

                // Cartes stats globales
                _GlobalStatsRow(overview: overview),
                const SizedBox(height: 24),

                // Graphique modes de scan + taux global
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: _ScanMethodChart(stats: overview.scanMethodStats),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 3,
                      child: _GlobalAttendanceCard(overview: overview),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Liste des voyages avec checkpoints
                Text(
                  'Voyages (${overview.totalTrips})',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),

                if (overview.trips.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        'Aucun voyage pour le filtre selectionne.',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ),
                  )
                else
                  ...overview.trips.map((trip) => Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: _TripOverviewCard(trip: trip),
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
  final DashboardProvider provider;

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
                'Statistiques et suivi en temps reel',
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
        // Filtre statut
        _StatusFilterDropdown(
          value: provider.statusFilter,
          onChanged: provider.setStatusFilter,
        ),
        const SizedBox(width: 12),
        // Bouton refresh manuel
        IconButton(
          onPressed: provider.loadOverview,
          icon: const Icon(Icons.refresh, size: 20),
          tooltip: 'Rafraichir',
        ),
      ],
    );
  }
}

class _StatusFilterDropdown extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _StatusFilterDropdown({required this.value, required this.onChanged});

  static const _options = [
    ('ALL', 'Tous les statuts'),
    ('ACTIVE', 'En cours'),
    ('PLANNED', 'A venir'),
    ('COMPLETED', 'Termines'),
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
// Stats globales (4 cartes)
// ---------------------------------------------------------------------------

class _GlobalStatsRow extends StatelessWidget {
  final DashboardOverview overview;

  const _GlobalStatsRow({required this.overview});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _StatCard(
          label: 'Voyages actifs',
          value: overview.activeTrips.toString(),
          icon: Icons.directions_bus,
          color: Colors.green.shade600,
        )),
        const SizedBox(width: 12),
        Expanded(child: _StatCard(
          label: 'A venir',
          value: overview.plannedTrips.toString(),
          icon: Icons.schedule,
          color: Colors.blue.shade600,
        )),
        const SizedBox(width: 12),
        Expanded(child: _StatCard(
          label: 'Total eleves',
          value: overview.totalStudents.toString(),
          icon: Icons.people,
          color: Colors.indigo.shade600,
        )),
        const SizedBox(width: 12),
        Expanded(child: _StatCard(
          label: 'Taux presence global',
          value: '${overview.globalAttendanceRate.toStringAsFixed(1)}%',
          icon: Icons.check_circle_outline,
          color: overview.globalAttendanceRate >= 80
              ? Colors.green.shade600
              : overview.globalAttendanceRate >= 50
                  ? Colors.orange.shade600
                  : Colors.red.shade600,
        )),
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
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Graphique modes de scan (Pie chart)
// ---------------------------------------------------------------------------

class _ScanMethodChart extends StatelessWidget {
  final ScanMethodStats stats;

  const _ScanMethodChart({required this.stats});

  @override
  Widget build(BuildContext context) {
    final hasData = stats.total > 0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Modes de scan', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          if (!hasData)
            SizedBox(
              height: 160,
              child: Center(
                child: Text('Aucun scan enregistre', style: TextStyle(color: Colors.grey.shade500)),
              ),
            )
          else
            SizedBox(
              height: 160,
              child: Row(
                children: [
                  Expanded(
                    child: PieChart(
                      PieChartData(
                        sectionsSpace: 2,
                        centerSpaceRadius: 30,
                        sections: _buildSections(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Legend(color: Colors.blue.shade600, label: 'NFC', count: stats.nfc),
                      const SizedBox(height: 8),
                      _Legend(color: Colors.orange.shade600, label: 'QR Physique', count: stats.qrPhysical),
                      const SizedBox(height: 8),
                      _Legend(color: Colors.purple.shade600, label: 'QR Digital', count: stats.qrDigital),
                      const SizedBox(height: 8),
                      _Legend(color: Colors.grey.shade600, label: 'Manuel', count: stats.manual),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  List<PieChartSectionData> _buildSections() {
    final total = stats.total.toDouble();
    if (total == 0) return [];

    return [
      if (stats.nfc > 0)
        PieChartSectionData(
          value: stats.nfc.toDouble(),
          color: Colors.blue.shade600,
          title: '${(stats.nfc / total * 100).toStringAsFixed(0)}%',
          titleStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
          radius: 40,
        ),
      if (stats.qrPhysical > 0)
        PieChartSectionData(
          value: stats.qrPhysical.toDouble(),
          color: Colors.orange.shade600,
          title: '${(stats.qrPhysical / total * 100).toStringAsFixed(0)}%',
          titleStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
          radius: 40,
        ),
      if (stats.qrDigital > 0)
        PieChartSectionData(
          value: stats.qrDigital.toDouble(),
          color: Colors.purple.shade600,
          title: '${(stats.qrDigital / total * 100).toStringAsFixed(0)}%',
          titleStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
          radius: 40,
        ),
      if (stats.manual > 0)
        PieChartSectionData(
          value: stats.manual.toDouble(),
          color: Colors.grey.shade600,
          title: '${(stats.manual / total * 100).toStringAsFixed(0)}%',
          titleStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
          radius: 40,
        ),
    ];
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;
  final int count;

  const _Legend({required this.color, required this.label, required this.count});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text('$label ($count)', style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Carte taux de presence global
// ---------------------------------------------------------------------------

class _GlobalAttendanceCard extends StatelessWidget {
  final DashboardOverview overview;

  const _GlobalAttendanceCard({required this.overview});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Resume', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          _SummaryRow(label: 'Total voyages', value: overview.totalTrips.toString()),
          _SummaryRow(label: 'Voyages termines', value: overview.completedTrips.toString()),
          _SummaryRow(label: 'Total scans', value: overview.totalAttendances.toString()),
          _SummaryRow(label: 'Taux presence global', value: '${overview.globalAttendanceRate.toStringAsFixed(1)}%'),
          const SizedBox(height: 12),
          // Barre de progression globale
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: overview.globalAttendanceRate / 100,
              minHeight: 8,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(
                overview.globalAttendanceRate >= 80
                    ? Colors.green.shade600
                    : overview.globalAttendanceRate >= 50
                        ? Colors.orange.shade600
                        : Colors.red.shade600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;

  const _SummaryRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Carte voyage avec graphe checkpoints
// ---------------------------------------------------------------------------

class _TripOverviewCard extends StatelessWidget {
  final DashboardTripSummary trip;

  const _TripOverviewCard({required this.trip});

  @override
  Widget build(BuildContext context) {
    final statusInfo = _statusInfo(trip.status);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // En-tete : destination + statut + taux
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      trip.destination,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _StatusBadge(label: statusInfo.$1, color: statusInfo.$2),
                        const SizedBox(width: 12),
                        Text(
                          _formatDate(trip.date),
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                        const SizedBox(width: 12),
                        Icon(Icons.people, size: 14, color: Colors.grey.shade500),
                        const SizedBox(width: 4),
                        Text(
                          '${trip.totalPresent}/${trip.totalStudents}',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                        ),
                        const SizedBox(width: 12),
                        Icon(Icons.flag, size: 14, color: Colors.grey.shade500),
                        const SizedBox(width: 4),
                        Text(
                          '${trip.closedCheckpoints}/${trip.totalCheckpoints} checkpoints',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Taux de presence du voyage
              _CircularRate(rate: trip.attendanceRate),
            ],
          ),

          // Graphique bar chart des checkpoints (si il y en a)
          if (trip.checkpoints.isNotEmpty) ...[
            const SizedBox(height: 16),
            SizedBox(
              height: 160,
              child: _CheckpointBarChart(
                checkpoints: trip.checkpoints,
                totalStudents: trip.totalStudents,
              ),
            ),
          ],

          // Dernier checkpoint
          if (trip.lastCheckpoint != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.location_on, size: 14, color: Colors.grey.shade500),
                const SizedBox(width: 4),
                Text(
                  'Dernier checkpoint : ${trip.lastCheckpoint!.name} (${trip.lastCheckpoint!.attendanceRate.toStringAsFixed(0)}%)',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  (String, Color) _statusInfo(String status) {
    return switch (status) {
      'ACTIVE' => ('En cours', Colors.green.shade600),
      'PLANNED' => ('A venir', Colors.blue.shade600),
      'COMPLETED' => ('Termine', Colors.grey.shade600),
      _ => (status, Colors.grey),
    };
  }

  String _formatDate(DateTime date) {
    const months = [
      'jan', 'fev', 'mar', 'avr', 'mai', 'juin',
      'juil', 'aout', 'sep', 'oct', 'nov', 'dec',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }
}

// ---------------------------------------------------------------------------
// Badge statut
// ---------------------------------------------------------------------------

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
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Taux circulaire
// ---------------------------------------------------------------------------

class _CircularRate extends StatelessWidget {
  final double rate;

  const _CircularRate({required this.rate});

  @override
  Widget build(BuildContext context) {
    final color = rate >= 80
        ? Colors.green.shade600
        : rate >= 50
            ? Colors.orange.shade600
            : Colors.red.shade600;

    return SizedBox(
      width: 56,
      height: 56,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CircularProgressIndicator(
            value: rate / 100,
            strokeWidth: 5,
            backgroundColor: Colors.grey.shade200,
            valueColor: AlwaysStoppedAnimation(color),
          ),
          Center(
            child: Text(
              '${rate.toStringAsFixed(0)}%',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bar chart presences par checkpoint
// ---------------------------------------------------------------------------

class _CheckpointBarChart extends StatelessWidget {
  final List<CheckpointSummary> checkpoints;
  final int totalStudents;

  const _CheckpointBarChart({required this.checkpoints, required this.totalStudents});

  @override
  Widget build(BuildContext context) {
    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: 100,
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final cp = checkpoints[groupIndex];
              return BarTooltipItem(
                '${cp.name}\n${cp.totalPresent}/${cp.totalExpected} (${cp.attendanceRate.toStringAsFixed(0)}%)',
                const TextStyle(color: Colors.white, fontSize: 11),
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          show: true,
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 32,
              getTitlesWidget: (value, meta) {
                if (value % 25 == 0) {
                  return Text('${value.toInt()}%', style: TextStyle(fontSize: 10, color: Colors.grey.shade600));
                }
                return const SizedBox.shrink();
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 32,
              getTitlesWidget: (value, meta) {
                final idx = value.toInt();
                if (idx < 0 || idx >= checkpoints.length) return const SizedBox.shrink();
                final name = checkpoints[idx].name;
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    name.length > 10 ? '${name.substring(0, 10)}...' : name,
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade700),
                    textAlign: TextAlign.center,
                  ),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          show: true,
          horizontalInterval: 25,
          getDrawingHorizontalLine: (value) => FlLine(
            color: Colors.grey.shade200,
            strokeWidth: 1,
          ),
        ),
        barGroups: checkpoints.asMap().entries.map((e) {
          final rate = e.value.attendanceRate;
          final color = rate >= 80
              ? Colors.green.shade500
              : rate >= 50
                  ? Colors.orange.shade500
                  : Colors.red.shade500;
          return BarChartGroupData(
            x: e.key,
            barRods: [
              BarChartRodData(
                toY: rate,
                color: color,
                width: 20,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Etat d'erreur
// ---------------------------------------------------------------------------

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
          const SizedBox(height: 16),
          Text(message, style: TextStyle(color: Colors.red.shade700)),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Reessayer'),
          ),
        ],
      ),
    );
  }
}
