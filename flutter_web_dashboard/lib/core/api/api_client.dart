import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../constants.dart';

/// Client HTTP centralisé pour les appels à l'API FastAPI.
/// Gère la base URL et les en-têtes communs.
class ApiClient {
  final String baseUrl;

  ApiClient({String? baseUrl}) : baseUrl = baseUrl ?? kApiBaseUrl;

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
}

/// Exception levée lors d'une erreur d'appel API.
class ApiException implements Exception {
  final int statusCode;
  final String message;

  const ApiException({required this.statusCode, required this.message});

  @override
  String toString() => 'ApiException($statusCode): $message';
}
