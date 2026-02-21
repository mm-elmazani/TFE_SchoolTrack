import 'package:flutter/material.dart';
import '../providers/trip_provider.dart';

/// Carte affichant le résumé d'un voyage dans la grille de la liste.
/// Conforme à la maquette V1 : statut coloré, date, destination, nb élèves.
class TripCard extends StatelessWidget {
  final Trip trip;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const TripCard({
    super.key,
    required this.trip,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final statusInfo = _statusInfo(trip.status);

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // En-tête : titre + menu actions
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      trip.destination,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, size: 20),
                    onSelected: (value) {
                      if (value == 'edit') onEdit();
                      if (value == 'delete') onDelete();
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit, size: 16),
                            SizedBox(width: 8),
                            Text('Modifier'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline, size: 16, color: Colors.red),
                            SizedBox(width: 8),
                            Text('Supprimer', style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Badge statut
              _StatusBadge(label: statusInfo.$1, color: statusInfo.$2),
              const SizedBox(height: 16),

              // Infos : date + nb élèves
              _InfoRow(
                icon: Icons.calendar_today_outlined,
                text: _formatDate(trip.date),
              ),
              const SizedBox(height: 6),
              _InfoRow(
                icon: Icons.people_outline,
                text: '${trip.totalStudents} élève${trip.totalStudents > 1 ? 's' : ''}',
              ),

              // Description (si présente)
              if (trip.description != null && trip.description!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  trip.description!,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Retourne le libellé et la couleur selon le statut
  (String, Color) _statusInfo(String status) {
    return switch (status) {
      'ACTIVE' => ('En cours', Colors.green.shade600),
      'PLANNED' => ('À venir', Colors.blue.shade600),
      'COMPLETED' => ('Terminé', Colors.grey.shade600),
      'ARCHIVED' => ('Archivé', Colors.brown.shade400),
      _ => (status, Colors.grey),
    };
  }

  String _formatDate(DateTime date) {
    const months = [
      'jan', 'fév', 'mar', 'avr', 'mai', 'juin',
      'juil', 'août', 'sep', 'oct', 'nov', 'déc',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }
}

/// Badge coloré affichant le statut du voyage
class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Ligne d'information avec icône et texte
class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 15, color: Colors.grey.shade500),
        const SizedBox(width: 6),
        Text(text, style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
      ],
    );
  }
}
