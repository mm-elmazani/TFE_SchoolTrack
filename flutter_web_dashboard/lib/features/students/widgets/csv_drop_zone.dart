import 'dart:typed_data';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/student_import_provider.dart';
import '../../../core/constants.dart';

/// Zone Drag & Drop pour la sélection d'un fichier CSV élèves.
/// Supporte :
///   - Glisser-déposer un fichier depuis l'explorateur
///   - Cliquer sur "Parcourir" pour ouvrir le sélecteur de fichier natif
/// Valide l'extension .csv côté client avant d'appeler le provider.
class CsvDropZone extends StatefulWidget {
  const CsvDropZone({super.key});

  @override
  State<CsvDropZone> createState() => _CsvDropZoneState();
}

class _CsvDropZoneState extends State<CsvDropZone> {
  bool _isDraggingOver = false;

  /// Valide et charge un fichier à partir de ses bytes et de son nom.
  /// Affiche un SnackBar si l'extension n'est pas .csv.
  void _handleFile(Uint8List bytes, String filename) {
    final ext = filename.split('.').last.toLowerCase();
    if (!kAllowedCsvExtensions.contains(ext)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Fichier invalide : "$filename" — seuls les fichiers .csv sont acceptés.',
          ),
          backgroundColor: Colors.orange.shade700,
        ),
      );
      return;
    }
    if (bytes.length > kMaxCsvSizeBytes) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Fichier trop volumineux (max 5 Mo).'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    context.read<StudentImportProvider>().setFile(bytes, filename);
  }

  /// Ouvre le sélecteur de fichier natif du navigateur (web).
  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: kAllowedCsvExtensions,
      withData: true,
    );
    if (result != null && result.files.isNotEmpty) {
      final file = result.files.first;
      if (file.bytes != null) {
        _handleFile(file.bytes!, file.name);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StudentImportProvider>();
    final isLoading = provider.state == ImportState.loading;
    final hasFile = provider.hasFileSelected;
    final filename = provider.selectedFileName;

    // Couleur de la bordure selon l'état
    Color borderColor;
    if (_isDraggingOver) {
      borderColor = Theme.of(context).colorScheme.primary;
    } else if (hasFile) {
      borderColor = Colors.green.shade600;
    } else {
      borderColor = Colors.grey.shade400;
    }

    return DropTarget(
      onDragEntered: (_) => setState(() => _isDraggingOver = true),
      onDragExited: (_) => setState(() => _isDraggingOver = false),
      onDragDone: (details) {
        setState(() => _isDraggingOver = false);
        if (details.files.isNotEmpty) {
          final xFile = details.files.first;
          xFile.readAsBytes().then((bytes) {
            _handleFile(bytes, xFile.name);
          });
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        height: 220,
        decoration: BoxDecoration(
          color: _isDraggingOver
              ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3)
              : hasFile
                  ? Colors.green.shade50
                  : Colors.grey.shade50,
          border: Border.all(
            color: borderColor,
            width: 2,
            style: BorderStyle.solid,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    hasFile ? Icons.check_circle_outline : Icons.upload_file,
                    size: 48,
                    color: hasFile
                        ? Colors.green.shade600
                        : _isDraggingOver
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey.shade500,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    hasFile
                        ? filename ?? 'Fichier sélectionné'
                        : _isDraggingOver
                            ? 'Relâchez le fichier ici'
                            : 'Glissez-déposez votre fichier CSV ici',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: hasFile
                              ? Colors.green.shade700
                              : Colors.grey.shade700,
                          fontWeight: hasFile ? FontWeight.w600 : FontWeight.normal,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  if (!hasFile) ...[
                    const SizedBox(height: 4),
                    Text(
                      'ou',
                      style: TextStyle(color: Colors.grey.shade500),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _pickFile,
                      icon: const Icon(Icons.folder_open, size: 18),
                      label: const Text('Parcourir'),
                    ),
                  ],
                  if (hasFile) ...[
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: () => context.read<StudentImportProvider>().reset(),
                      icon: const Icon(Icons.close, size: 16),
                      label: const Text('Changer de fichier'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}
