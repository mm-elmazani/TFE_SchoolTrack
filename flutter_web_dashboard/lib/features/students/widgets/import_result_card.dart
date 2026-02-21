import 'package:flutter/material.dart';
import '../providers/student_import_provider.dart';

/// Carte affichant le résultat d'un import CSV élèves.
/// Montre le nombre d'élèves importés, rejetés et la liste des erreurs.
class ImportResultCard extends StatelessWidget {
  final ImportResult result;

  const ImportResultCard({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final hasErrors = result.errors.isNotEmpty;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // En-tête avec le titre
            Row(
              children: [
                Icon(
                  hasErrors ? Icons.warning_amber_rounded : Icons.check_circle,
                  color: hasErrors ? Colors.orange.shade700 : Colors.green.shade600,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Text(
                  'Résultat de l\'import',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Statistiques en ligne
            Row(
              children: [
                _StatChip(
                  label: 'Importés',
                  value: result.imported,
                  color: Colors.green.shade600,
                  icon: Icons.person_add,
                ),
                const SizedBox(width: 12),
                _StatChip(
                  label: 'Rejetés',
                  value: result.rejected,
                  color: result.rejected > 0
                      ? Colors.orange.shade700
                      : Colors.grey.shade500,
                  icon: Icons.person_off,
                ),
              ],
            ),

            // Liste des erreurs (si présentes)
            if (hasErrors) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              Text(
                'Lignes rejetées :',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Colors.orange.shade800,
                    ),
              ),
              const SizedBox(height: 8),
              Container(
                constraints: const BoxConstraints(maxHeight: 200),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  itemCount: result.errors.length,
                  separatorBuilder: (_, __) => const Divider(height: 8),
                  itemBuilder: (context, index) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: 16,
                          color: Colors.orange.shade700,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            result.errors[index],
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.orange.shade900,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Widget interne affichant une statistique (nombre + libellé).
class _StatChip extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  final IconData icon;

  const _StatChip({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value.toString(),
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              Text(
                label,
                style: TextStyle(fontSize: 12, color: color),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
