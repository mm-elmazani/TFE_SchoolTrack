import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../constants.dart';

/// Client HTTP centralisé pour les appels à l'API FastAPI.
/// Gère la base URL et les en-têtes communs.
class ApiClient {
  final String baseUrl;

  ApiClient({String? baseUrl}) : baseUrl = baseUrl ?? kApiBaseUrl;

  // ─── Helpers internes ──────────────────────────────────────────────────────

  Map<String, String> get _jsonHeaders => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

  /// Effectue une requête GET et retourne le corps JSON décodé.
  Future<dynamic> _get(String path) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl$path'),
        headers: _jsonHeaders,
      );
      return _handleResponse(response);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(statusCode: 0, message: 'Impossible de contacter le serveur : $e');
    }
  }

  /// Effectue une requête POST avec un corps JSON.
  Future<dynamic> _post(String path, Map<String, dynamic> body) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl$path'),
        headers: _jsonHeaders,
        body: jsonEncode(body),
      );
      return _handleResponse(response);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(statusCode: 0, message: 'Impossible de contacter le serveur : $e');
    }
  }

  /// Effectue une requête PUT avec un corps JSON.
  Future<dynamic> _put(String path, Map<String, dynamic> body) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl$path'),
        headers: _jsonHeaders,
        body: jsonEncode(body),
      );
      return _handleResponse(response);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(statusCode: 0, message: 'Impossible de contacter le serveur : $e');
    }
  }

  /// Effectue une requête DELETE.
  Future<void> _delete(String path) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl$path'),
        headers: _jsonHeaders,
      );
      if (response.statusCode != 200 && response.statusCode != 204) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        throw ApiException(
          statusCode: response.statusCode,
          message: (body['detail'] ?? 'Erreur inconnue').toString(),
        );
      }
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(statusCode: 0, message: 'Impossible de contacter le serveur : $e');
    }
  }

  /// Vérifie le code HTTP et retourne le corps décodé, ou lève une ApiException.
  dynamic _handleResponse(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return null;
      return jsonDecode(response.body);
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    throw ApiException(
      statusCode: response.statusCode,
      message: (body['detail'] ?? 'Erreur inconnue').toString(),
    );
  }

  // ─── US 1.1 — Import CSV élèves ───────────────────────────────────────────

  /// Envoie un fichier CSV en multipart/form-data vers POST /api/v1/students/upload.
  Future<Map<String, dynamic>> uploadCsv(Uint8List bytes, String filename) async {
    final uri = Uri.parse('$baseUrl/api/v1/students/upload');
    final request = http.MultipartRequest('POST', uri);
    request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));

    try {
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      return _handleResponse(response) as Map<String, dynamic>;
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(statusCode: 0, message: 'Impossible de contacter le serveur : $e');
    }
  }

  // ─── US 1.2 — CRUD Voyages ────────────────────────────────────────────────

  /// Récupère la liste de tous les voyages.
  Future<List<dynamic>> getTrips() async {
    return (await _get('/api/v1/trips')) as List<dynamic>;
  }

  /// Crée un nouveau voyage.
  /// [destination], [date] (format ISO "YYYY-MM-DD"), [classIds] (au moins 1), [description] optionnel.
  Future<Map<String, dynamic>> createTrip({
    required String destination,
    required String date,
    required List<String> classIds,
    String? description,
  }) async {
    final body = <String, dynamic>{
      'destination': destination,
      'date': date,
      'class_ids': classIds,
      if (description != null && description.isNotEmpty) 'description': description,
    };
    return (await _post('/api/v1/trips', body)) as Map<String, dynamic>;
  }

  /// Met à jour un voyage existant.
  /// Si [classIds] est fourni, les élèves du voyage sont recalculés depuis ces classes.
  Future<Map<String, dynamic>> updateTrip(
    String tripId, {
    String? destination,
    String? date,
    String? description,
    String? status,
    List<String>? classIds,
  }) async {
    final body = <String, dynamic>{
      if (destination != null) 'destination': destination,
      if (date != null) 'date': date,
      if (description != null) 'description': description,
      if (status != null) 'status': status,
      if (classIds != null) 'class_ids': classIds,
    };
    return (await _put('/api/v1/trips/$tripId', body)) as Map<String, dynamic>;
  }

  /// Supprime un voyage par son ID.
  Future<void> deleteTrip(String tripId) async {
    await _delete('/api/v1/trips/$tripId');
  }

  // ─── Classes (nécessaire pour le formulaire voyage) ───────────────────────

  /// Récupère la liste de toutes les classes (pour la sélection dans le formulaire voyage).
  Future<List<dynamic>> getClasses() async {
    return (await _get('/api/v1/classes')) as List<dynamic>;
  }
}

/// Exception levée lors d'une erreur d'appel API.
class ApiException implements Exception {
  final int statusCode;
  final String message;

  const ApiException({required this.statusCode, required this.message});

  @override
  String toString() => 'ApiException($statusCode): $message';
}
