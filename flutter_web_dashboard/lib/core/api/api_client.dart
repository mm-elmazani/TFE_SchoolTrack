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
      if (response.statusCode == 200 || response.statusCode == 204) return;
      _handleResponse(response);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(statusCode: 0, message: 'Impossible de contacter le serveur : $e');
    }
  }

  /// Vérifie le code HTTP et retourne le corps décodé, ou lève une ApiException.
  /// Gère les corps de réponse non-JSON pour les erreurs.
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

  // ─── US 1.3 — Élèves ─────────────────────────────────────────────────────

  /// Retourne la liste de tous les élèves (GET /api/v1/students).
  Future<List<Map<String, dynamic>>> getStudents() async {
    final data = await _get('/api/v1/students');
    return List<Map<String, dynamic>>.from(data as List);
  }

  /// Crée un élève manuellement (POST /api/v1/students).
  Future<Map<String, dynamic>> createStudent({
    required String firstName,
    required String lastName,
    String? email,
  }) async {
    final body = <String, dynamic>{
      'first_name': firstName,
      'last_name': lastName,
      if (email != null && email.isNotEmpty) 'email': email,
    };
    return (await _post('/api/v1/students', body)) as Map<String, dynamic>;
  }

  /// Met à jour un élève (PUT /api/v1/students/{id}).
  Future<Map<String, dynamic>> updateStudent(
    String studentId, {
    String? firstName,
    String? lastName,
    String? email,
  }) async {
    final body = <String, dynamic>{
      if (firstName != null) 'first_name': firstName,
      if (lastName != null) 'last_name': lastName,
      'email': email, // null autorisé (efface l'email)
    };
    return (await _put('/api/v1/students/$studentId', body)) as Map<String, dynamic>;
  }

  /// Supprime un élève (DELETE /api/v1/students/{id}).
  Future<void> deleteStudent(String studentId) async {
    await _delete('/api/v1/students/$studentId');
  }

  // ─── US 1.3 — Classes ────────────────────────────────────────────────────

  /// Retourne toutes les classes (GET /api/v1/classes).
  Future<List<Map<String, dynamic>>> getClasses() async {
    final data = await _get('/api/v1/classes');
    return List<Map<String, dynamic>>.from(data as List);
  }

  /// Crée une classe (POST /api/v1/classes).
  Future<Map<String, dynamic>> createClass(String name, {String? year}) async {
    final body = <String, dynamic>{'name': name};
    if (year != null && year.isNotEmpty) body['year'] = year;
    return (await _post('/api/v1/classes', body)) as Map<String, dynamic>;
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
    return (await _put('/api/v1/classes/$classId', body)) as Map<String, dynamic>;
  }

  /// Supprime une classe (DELETE /api/v1/classes/{id}).
  Future<void> deleteClass(String classId) async {
    await _delete('/api/v1/classes/$classId');
  }

  /// Retourne les IDs des élèves assignés à une classe (GET /api/v1/classes/{id}/students).
  Future<List<String>> getClassStudentIds(String classId) async {
    final data = await _get('/api/v1/classes/$classId/students');
    return List<String>.from(data as List);
  }

  /// Assigne des élèves à une classe (POST /api/v1/classes/{id}/students).
  Future<Map<String, dynamic>> assignStudents(
    String classId,
    List<String> studentIds,
  ) async {
    return (await _post(
      '/api/v1/classes/$classId/students',
      {'student_ids': studentIds},
    )) as Map<String, dynamic>;
  }

  /// Retire un élève d'une classe (DELETE /api/v1/classes/{id}/students/{sid}).
  Future<void> removeStudentFromClass(String classId, String studentId) async {
    await _delete('/api/v1/classes/$classId/students/$studentId');
  }

  // ─── US 1.2 — CRUD Voyages ────────────────────────────────────────────────

  /// Récupère la liste de tous les voyages (GET /api/v1/trips).
  Future<List<Map<String, dynamic>>> getTrips() async {
    final data = await _get('/api/v1/trips');
    return List<Map<String, dynamic>>.from(data as List);
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

  /// Supprime (archive) un voyage par son ID.
  Future<void> deleteTrip(String tripId) async {
    await _delete('/api/v1/trips/$tripId');
  }

  // ─── US 1.5 — Assignation bracelets ──────────────────────────────────────

  /// Retourne les élèves d'un voyage avec leur statut d'assignation bracelet.
  Future<Map<String, dynamic>> getTripStudents(String tripId) async {
    return (await _get('/api/v1/trips/$tripId/students')) as Map<String, dynamic>;
  }

  /// Assigne un bracelet à un élève pour un voyage.
  Future<Map<String, dynamic>> assignToken({
    required String tokenUid,
    required String studentId,
    required String tripId,
    required String assignmentType,
  }) async {
    return (await _post('/api/v1/tokens/assign', {
      'token_uid': tokenUid,
      'student_id': studentId,
      'trip_id': tripId,
      'assignment_type': assignmentType,
    })) as Map<String, dynamic>;
  }

  /// Réassigne un bracelet avec justification obligatoire.
  Future<Map<String, dynamic>> reassignToken({
    required String tokenUid,
    required String studentId,
    required String tripId,
    required String assignmentType,
    required String justification,
  }) async {
    return (await _post('/api/v1/tokens/reassign', {
      'token_uid': tokenUid,
      'student_id': studentId,
      'trip_id': tripId,
      'assignment_type': assignmentType,
      'justification': justification,
    })) as Map<String, dynamic>;
  }

  /// Libère tous les bracelets actifs d'un voyage.
  /// Retourne { trip_id, released_count }.
  Future<Map<String, dynamic>> releaseTripTokens(String tripId) async {
    return (await _post('/api/v1/trips/$tripId/release-tokens', {})) as Map<String, dynamic>;
  }

  /// Envoie les QR codes digitaux par email pour tous les élèves d'un voyage.
  /// Retourne { trip_id, sent_count, already_sent_count, no_email_count, errors }.
  Future<Map<String, dynamic>> sendQrEmails(String tripId) async {
    return (await _post('/api/v1/trips/$tripId/send-qr-emails', {})) as Map<String, dynamic>;
  }

  /// Retourne l'URL d'export CSV des assignations d'un voyage.
  String getExportUrl(String tripId) =>
      '$baseUrl/api/v1/trips/$tripId/assignments/export';
}

/// Exception levée lors d'une erreur d'appel API.
class ApiException implements Exception {
  final int statusCode;
  final String message;

  const ApiException({required this.statusCode, required this.message});

  @override
  String toString() => 'ApiException($statusCode): $message';
}
