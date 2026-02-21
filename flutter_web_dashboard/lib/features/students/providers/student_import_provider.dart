import 'package:flutter/foundation.dart';
import '../../../core/api/api_client.dart';

/// États possibles de l'import CSV
enum ImportState { idle, loading, success, error }

/// Résultat d'un import CSV renvoyé par l'API
class ImportResult {
  final int imported;
  final int rejected;
  final List<String> errors;

  const ImportResult({
    required this.imported,
    required this.rejected,
    required this.errors,
  });

  /// Construit un ImportResult depuis la réponse JSON de l'API
  factory ImportResult.fromJson(Map<String, dynamic> json) {
    final rawErrors = json['errors'] as List<dynamic>? ?? [];
    return ImportResult(
      imported: (json['imported'] as int?) ?? 0,
      rejected: (json['rejected'] as int?) ?? 0,
      errors: rawErrors.map((e) => e.toString()).toList(),
    );
  }
}

/// Provider gérant l'état de l'import CSV élèves (US 1.1).
/// Expose l'état courant, le fichier sélectionné et le résultat d'import.
class StudentImportProvider extends ChangeNotifier {
  final ApiClient _apiClient;

  StudentImportProvider({ApiClient? apiClient})
      : _apiClient = apiClient ?? ApiClient();

  ImportState _state = ImportState.idle;
  ImportResult? _result;
  String? _errorMessage;
  String? _selectedFileName;
  Uint8List? _selectedFileBytes;

  // --- Getters ---
  ImportState get state => _state;
  ImportResult? get result => _result;
  String? get errorMessage => _errorMessage;
  String? get selectedFileName => _selectedFileName;
  bool get hasFileSelected => _selectedFileBytes != null;

  /// Stocke le fichier sélectionné (Drag & Drop ou Parcourir)
  void setFile(Uint8List bytes, String filename) {
    _selectedFileBytes = bytes;
    _selectedFileName = filename;
    _state = ImportState.idle;
    _result = null;
    _errorMessage = null;
    notifyListeners();
  }

  /// Réinitialise la sélection et le résultat
  void reset() {
    _selectedFileBytes = null;
    _selectedFileName = null;
    _state = ImportState.idle;
    _result = null;
    _errorMessage = null;
    notifyListeners();
  }

  /// Lance l'upload CSV vers l'API FastAPI.
  /// Met à jour l'état selon la réponse reçue.
  Future<void> uploadCsv() async {
    if (_selectedFileBytes == null || _selectedFileName == null) return;

    _state = ImportState.loading;
    _errorMessage = null;
    _result = null;
    notifyListeners();

    try {
      final json = await _apiClient.uploadCsv(
        _selectedFileBytes!,
        _selectedFileName!,
      );
      _result = ImportResult.fromJson(json);
      _state = ImportState.success;
    } on ApiException catch (e) {
      _errorMessage = e.message;
      _state = ImportState.error;
    } catch (e) {
      _errorMessage = 'Erreur inattendue : $e';
      _state = ImportState.error;
    }

    notifyListeners();
  }
}
