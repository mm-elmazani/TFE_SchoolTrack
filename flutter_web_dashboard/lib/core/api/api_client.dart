import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../constants.dart';

/// Client HTTP centralisé pour les appels à l'API FastAPI.
/// Gère la base URL et les en-têtes communs.
class ApiClient {
  final String baseUrl;

  ApiClient({String? baseUrl}) : baseUrl = baseUrl ?? kApiBaseUrl;

  // ----------------------------------------------------------------
  // Helpers privés
  // ----------------------------------------------------------------

  /// Effectue une requête GET et retourne le JSON décodé.
  Future<dynamic> _get(String path) async {
    final uri = Uri.parse('$baseUrl$path');
    try {
      final response = await http.get(uri);
      final body = jsonDecode(response.body);
      if (response.statusCode == 200) return body;
      final detail =
          (body as Map<String, dynamic>)['detail'] ?? 'Erreur inconnue';
      throw ApiException(
        statusCode: response.statusCode,
        message: detail.toString(),
      );
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(
        statusCode: 0,
        message: 'Impossible de contacter le serveur : $e',
      );
    }
  }

  /// Effectue une requête POST JSON et retourne le JSON décodé.
  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    final uri = Uri.parse('$baseUrl$path');
    try {
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
      final responseBody = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 || response.statusCode == 201) {
        return responseBody;
      }
      final detail = responseBody['detail'] ?? 'Erreur inconnue';
      throw ApiException(
        statusCode: response.statusCode,
        message: detail.toString(),
      );
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(
        statusCode: 0,
        message: 'Impossible de contacter le serveur : $e',
      );
    }
  }

  // ----------------------------------------------------------------
  // US 1.1 — Import CSV élèves
  // ----------------------------------------------------------------

  /// Envoie un fichier CSV en multipart/form-data vers POST /api/v1/students/upload.
  ///
  /// [bytes] : contenu binaire du fichier CSV
  /// [filename] : nom du fichier (ex. "eleves.csv")
  ///
  /// Retourne le corps JSON de la réponse sous forme de Map.
  /// Lance une [ApiException] en cas d'erreur HTTP ou réseau.
  Future<Map<String, dynamic>> uploadCsv(
    Uint8List bytes,
    String filename,
  ) async {
    final uri = Uri.parse('$baseUrl/api/v1/students/upload');

    final request = http.MultipartRequest('POST', uri);
    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: filename,
      ),
    );

    try {
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      final body = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200 || response.statusCode == 201) {
        return body;
      } else {
        final detail = body['detail'] ?? 'Erreur inconnue';
        throw ApiException(
          statusCode: response.statusCode,
          message: detail.toString(),
        );
      }
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(
        statusCode: 0,
        message: 'Impossible de contacter le serveur : $e',
      );
    }
  }

  // ----------------------------------------------------------------
  // US 1.2 / 1.5 — Voyages
  // ----------------------------------------------------------------

  /// Retourne la liste de tous les voyages actifs (hors archivés).
  Future<List<Map<String, dynamic>>> getTrips() async {
    final data = await _get('/api/v1/trips');
    return (data as List<dynamic>).cast<Map<String, dynamic>>();
  }

  // ----------------------------------------------------------------
  // US 1.5 — Assignation bracelets
  // ----------------------------------------------------------------

  /// Retourne les élèves d'un voyage avec leur statut d'assignation bracelet.
  Future<Map<String, dynamic>> getTripStudents(String tripId) async {
    final data = await _get('/api/v1/trips/$tripId/students');
    return data as Map<String, dynamic>;
  }

  /// Assigne un bracelet à un élève pour un voyage.
  Future<Map<String, dynamic>> assignToken({
    required String tokenUid,
    required String studentId,
    required String tripId,
    required String assignmentType,
  }) async {
    return _post('/api/v1/tokens/assign', {
      'token_uid': tokenUid,
      'student_id': studentId,
      'trip_id': tripId,
      'assignment_type': assignmentType,
    });
  }

  /// Réassigne un bracelet avec justification obligatoire.
  Future<Map<String, dynamic>> reassignToken({
    required String tokenUid,
    required String studentId,
    required String tripId,
    required String assignmentType,
    required String justification,
  }) async {
    return _post('/api/v1/tokens/reassign', {
      'token_uid': tokenUid,
      'student_id': studentId,
      'trip_id': tripId,
      'assignment_type': assignmentType,
      'justification': justification,
    });
  }

  /// Libère tous les bracelets actifs d'un voyage.
  /// Retourne { trip_id, released_count }.
  Future<Map<String, dynamic>> releaseTripTokens(String tripId) async {
    final uri = Uri.parse('$baseUrl/api/v1/trips/$tripId/release-tokens');
    try {
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200) return body;
      throw ApiException(
        statusCode: response.statusCode,
        message: body['detail']?.toString() ?? 'Erreur inconnue',
      );
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(
        statusCode: 0,
        message: 'Impossible de contacter le serveur : $e',
      );
    }
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
