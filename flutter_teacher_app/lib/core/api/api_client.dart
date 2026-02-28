/// Client HTTP pour communiquer avec l'API FastAPI SchoolTrack.
library;

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants.dart';
import '../../features/trips/models/offline_bundle.dart';
import '../../features/scan/models/checkpoint_create_result.dart';

/// Exception levée lors d'une erreur API (HTTP ou réseau).
class ApiException implements Exception {
  final String message;
  final int? statusCode;

  const ApiException(this.message, {this.statusCode});

  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// Client HTTP pour l'API SchoolTrack.
class ApiClient {
  final String baseUrl;
  final http.Client _http;

  ApiClient({String? baseUrl, http.Client? client})
      : baseUrl = baseUrl ?? kApiBaseUrl,
        _http = client ?? http.Client();

  // ----------------------------------------------------------------
  // Voyages
  // ----------------------------------------------------------------

  /// Récupère la liste des voyages actifs depuis l'API.
  /// Lève [ApiException] si le réseau est indisponible ou si l'API répond avec une erreur.
  Future<List<TripSummary>> getTrips() async {
    try {
      final response = await _http
          .get(Uri.parse('$baseUrl/api/v1/trips'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body) as List<dynamic>;
        return data
            .map((j) => TripSummary.fromJson(j as Map<String, dynamic>))
            .toList();
      }
      throw ApiException(
        'Erreur serveur (${response.statusCode})',
        statusCode: response.statusCode,
      );
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Impossible de contacter le serveur : $e');
    }
  }

  // ----------------------------------------------------------------
  // Checkpoints terrain (US 2.5)
  // ----------------------------------------------------------------

  /// Crée un checkpoint sur le backend (best-effort — retourne null si hors-ligne).
  ///
  /// Le checkpoint est d'abord créé localement en SQLite avant cet appel.
  /// Si le réseau est indisponible ou l'API répond avec une erreur, null est
  /// retourné silencieusement (l'appli continue en mode offline).
  Future<CheckpointCreateResult?> createCheckpoint(
    String tripId,
    String name,
  ) async {
    try {
      final response = await _http
          .post(
            Uri.parse('$baseUrl/api/v1/trips/$tripId/checkpoints'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'name': name}),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return CheckpointCreateResult(
          serverId: data['id'] as String,
          sequenceOrder: data['sequence_order'] as int,
        );
      }
      return null;
    } catch (_) {
      // Hors-ligne ou erreur réseau — mode offline, on continue sans erreur
      return null;
    }
  }

  // ----------------------------------------------------------------
  // Bundle offline
  // ----------------------------------------------------------------

  /// Télécharge le bundle de données offline pour un voyage.
  /// Endpoint : GET /api/v1/trips/{trip_id}/offline-data
  /// Lève [ApiException] si le réseau est indisponible ou si l'API répond avec une erreur.
  Future<OfflineDataBundle> getOfflineBundle(String tripId) async {
    try {
      final response = await _http
          .get(Uri.parse('$baseUrl/api/v1/trips/$tripId/offline-data'))
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data =
            jsonDecode(response.body) as Map<String, dynamic>;
        return OfflineDataBundle.fromJson(data);
      }
      if (response.statusCode == 404) {
        throw const ApiException('Voyage introuvable.', statusCode: 404);
      }
      throw ApiException(
        'Erreur serveur (${response.statusCode})',
        statusCode: response.statusCode,
      );
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Impossible de télécharger les données : $e');
    }
  }
}
