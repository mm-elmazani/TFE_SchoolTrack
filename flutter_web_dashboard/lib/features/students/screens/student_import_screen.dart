import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/student_import_provider.dart';
import '../widgets/csv_drop_zone.dart';
import '../widgets/import_result_card.dart';

/// Écran US 1.1 — Import CSV des élèves.
/// Permet à la Direction de charger un fichier CSV pour créer ou mettre à jour
/// les fiches élèves en base de données.
class StudentImportScreen extends StatelessWidget {
  const StudentImportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => StudentImportProvider(),
      child: const _StudentImportBody(),
    );
  }
}

class _StudentImportBody extends StatelessWidget {
  const _StudentImportBody();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StudentImportProvider>();
    final isLoading = provider.state == ImportState.loading;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Description
          Text(
            'Importer les élèves depuis un fichier CSV',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Le fichier doit contenir les colonnes : prenom, nom, email, classe. '
            'Les doublons (email existant) seront ignorés.',
            style: TextStyle(color: Colors.grey.shade600),
          ),
          const SizedBox(height: 24),

          // Zone Drag & Drop
          const CsvDropZone(),

          const SizedBox(height: 20),

          // Bouton Importer
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              onPressed:
                  (!provider.hasFileSelected || isLoading)
                      ? null
                      : () => context.read<StudentImportProvider>().uploadCsv(),
              icon: isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.cloud_upload),
              label: Text(isLoading ? 'Import en cours...' : 'Importer'),
            ),
          ),

          // Message d'erreur
          if (provider.state == ImportState.error) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.red.shade700, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      provider.errorMessage ?? 'Une erreur est survenue.',
                      style: TextStyle(color: Colors.red.shade800),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Carte de résultats (si succès)
          if (provider.state == ImportState.success && provider.result != null) ...[
            const SizedBox(height: 20),
            ImportResultCard(result: provider.result!),
          ],
        ],
      ),
    );
  }
}
