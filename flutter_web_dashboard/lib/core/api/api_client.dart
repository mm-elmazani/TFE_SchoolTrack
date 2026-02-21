import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../constants.dart';

/// Client HTTP centralisé pour les appels à l'API FastAPI.
/// Gère la base URL et les en-têtes communs.
class ApiClient {
  final String baseUrl;

  ApiClient({String? baseUrl}) : baseUrl = baseUrl ?? kApiBaseUrl;

  // ---------------------------------------------------------------------------
  // Méthodes HTTP génériques
  // ---------------------------------------------------------------------------

  Future<dynamic> _get(String path) async {
    final uri = Uri.parse('$baseUrl$path');
    try {
      final response = await http.get(uri);
      return _handleResponse(response);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(statusCode: 0, message: 'Impossible de contacter le serveur : $e');
    }
  }

  Future<dynamic> _post(String path, Map<String, dynamic> body) async {
    final uri = Uri.parse('$baseUrl$path');
    try {
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
      return _handleResponse(response);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(statusCode: 0, message: 'Impossible de contacter le serveur : $e');
    }
  }

  Future<dynamic> _put(String path, Map<String, dynamic> body) async {
    final uri = Uri.parse('$baseUrl$path');
    try {
      final response = await http.put(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
      return _handleResponse(response);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(statusCode: 0, message: 'Impossible de contacter le serveur : $e');
    }
  }

  Future<void> _delete(String path) async {
    final uri = Uri.parse('$baseUrl$path');
    try {
      final response = await http.delete(uri);
      if (response.statusCode == 204) return;
      _handleResponse(response);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(statusCode: 0, message: 'Impossible de contacter le serveur : $e');
    }
  }

  dynamic _handleResponse(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return null;
      return jsonDecode(response.body);
    }
    String detail;
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      detail = body['detail']?.toString() ?? 'Erreur inconnue';
    } catch (_) {
      detail = response.body.isNotEmpty ? response.body : 'Erreur inconnue';
    }
    throw ApiException(statusCode: response.statusCode, message: detail);
  }

  // ---------------------------------------------------------------------------
  // Élèves
  // ---------------------------------------------------------------------------

  /// Retourne la liste de tous les élèves (GET /api/v1/students).
  Future<List<Map<String, dynamic>>> getStudents() async {
    final data = await _get('/api/v1/students');
    return List<Map<String, dynamic>>.from(data as List);
  }

  /// Importe un fichier CSV d'élèves (POST /api/v1/students/upload).
  Future<Map<String, dynamic>> uploadCsv(Uint8List bytes, String filename) async {
    final uri = Uri.parse('$baseUrl/api/v1/students/upload');
    final request = http.MultipartRequest('POST', uri);
    request.files.add(
      http.MultipartFile.fromBytes('file', bytes, filename: filename),
    );
    try {
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 || response.statusCode == 201) return body;
      final detail = body['detail'] ?? 'Erreur inconnue';
      throw ApiException(statusCode: response.statusCode, message: detail.toString());
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(statusCode: 0, message: 'Impossible de contacter le serveur : $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Classes
  // ---------------------------------------------------------------------------

  /// Retourne toutes les classes (GET /api/v1/classes).
  Future<List<Map<String, dynamic>>> getClasses() async {
    final data = await _get('/api/v1/classes');
    return List<Map<String, dynamic>>.from(data as List);
  }

  /// Crée une classe (POST /api/v1/classes).
  Future<Map<String, dynamic>> createClass(String name, {String? year}) async {
    final body = <String, dynamic>{'name': name};
    if (year != null && year.isNotEmpty) body['year'] = year;
    final data = await _post('/api/v1/classes', body);
    return data as Map<String, dynamic>;
  }

  /// Met à jour une classe (PUT /api/v1/classes/{id}).
  Future<Map<String, dynamic>> updateClass(
    String classId, {
    String? name,
    String? year,
  }) async {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (year != null) body['year'] = year;
    final data = await _put('/api/v1/classes/$classId', body);
    return data as Map<String, dynamic>;
  }

  /// Supprime une classe (DELETE /api/v1/classes/{id}).
  Future<void> deleteClass(String classId) async {
    await _delete('/api/v1/classes/$classId');
  }

  /// Retourne les IDs des élèves déjà assignés à une classe (GET /api/v1/classes/{id}/students).
  Future<List<String>> getClassStudentIds(String classId) async {
    final data = await _get('/api/v1/classes/$classId/students');
    return List<String>.from(data as List);
  }

  /// Assigne des élèves à une classe (POST /api/v1/classes/{id}/students).
  Future<Map<String, dynamic>> assignStudents(
    String classId,
    List<String> studentIds,
  ) async {
    final data = await _post(
      '/api/v1/classes/$classId/students',
      {'student_ids': studentIds},
    );
    return data as Map<String, dynamic>;
  }

  /// Retire un élève d'une classe (DELETE /api/v1/classes/{id}/students/{sid}).
  Future<void> removeStudentFromClass(String classId, String studentId) async {
    await _delete('/api/v1/classes/$classId/students/$studentId');
  }

  // ---------------------------------------------------------------------------
  // Voyages
  // ---------------------------------------------------------------------------

  /// Retourne tous les voyages (GET /api/v1/trips).
  Future<List<Map<String, dynamic>>> getTrips() async {
    final data = await _get('/api/v1/trips');
    return List<Map<String, dynamic>>.from(data as List);
  }

  /// Crée un voyage (POST /api/v1/trips).
  Future<Map<String, dynamic>> createTrip(Map<String, dynamic> body) async {
    final data = await _post('/api/v1/trips', body);
    return data as Map<String, dynamic>;
  }

  /// Met à jour un voyage (PUT /api/v1/trips/{id}).
  Future<Map<String, dynamic>> updateTrip(
    String tripId,
    Map<String, dynamic> body,
  ) async {
    final data = await _put('/api/v1/trips/$tripId', body);
    return data as Map<String, dynamic>;
  }

  /// Archive un voyage (DELETE /api/v1/trips/{id}).
  Future<void> deleteTrip(String tripId) async {
    await _delete('/api/v1/trips/$tripId');
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
