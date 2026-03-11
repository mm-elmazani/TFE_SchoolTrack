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

  /// Token JWT injecte dans le header Authorization de chaque requete authentifiee.
  static String? authToken;

  /// Callback appele quand un 401 est recu (token expire).
  /// Doit rafraichir authToken et retourner true si le refresh a reussi.
  static Future<bool> Function()? onTokenExpired;

  /// Empeche les refreshs concurrents.
  static bool _isRefreshing = false;

  ApiClient({String? baseUrl, http.Client? client})
      : baseUrl = baseUrl ?? kApiBaseUrl,
        _http = client ?? http.Client();

  /// Tente de rafraichir le token. Retourne true si reussi.
  Future<bool> _tryRefresh() async {
    if (_isRefreshing || onTokenExpired == null) return false;
    _isRefreshing = true;
    try {
      return await onTokenExpired!();
    } finally {
      _isRefreshing = false;
    }
  }

  Map<String, String> get _authHeaders => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (authToken != null) 'Authorization': 'Bearer $authToken',
      };

  // ----------------------------------------------------------------
  // Voyages
  // ----------------------------------------------------------------

  /// Récupère la liste des voyages actifs depuis l'API.
  /// Lève [ApiException] si le réseau est indisponible ou si l'API répond avec une erreur.
  Future<List<TripSummary>> getTrips() async {
    try {
      final uri = Uri.parse('$baseUrl/api/v1/trips');
      var response = await _http
          .get(uri, headers: _authHeaders)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 401 && await _tryRefresh()) {
        response = await _http
            .get(uri, headers: _authHeaders)
            .timeout(const Duration(seconds: 10));
      }

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
            headers: _authHeaders,
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

  /// Clôture un checkpoint sur le backend (best-effort — retourne null si hors-ligne).
  ///
  /// Le statut est d'abord mis à jour localement en SQLite avant cet appel.
  /// Si le réseau est indisponible ou l'API répond avec une erreur, null est
  /// retourné silencieusement (l'appli continue en mode offline).
  Future<bool> closeCheckpoint(String checkpointId) async {
    try {
      final response = await _http
          .post(
            Uri.parse('$baseUrl/api/v1/checkpoints/$checkpointId/close'),
            headers: _authHeaders,
          )
          .timeout(const Duration(seconds: 10));

      return response.statusCode == 200;
    } catch (_) {
      // Hors-ligne ou erreur réseau — mode offline, on continue sans erreur
      return false;
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
      final uri = Uri.parse('$baseUrl/api/v1/trips/$tripId/offline-data');
      var response = await _http
          .get(uri, headers: _authHeaders)
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 401 && await _tryRefresh()) {
        response = await _http
            .get(uri, headers: _authHeaders)
            .timeout(const Duration(seconds: 30));
      }

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

  // ----------------------------------------------------------------
  // Authentification (US 6.1)
  // ----------------------------------------------------------------

  /// POST /api/v1/auth/login
  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
    String? totpCode,
  }) async {
    final body = <String, dynamic>{
      'email': email,
      'password': password,
      if (totpCode != null && totpCode.isNotEmpty) 'totp_code': totpCode,
    };
    try {
      final response = await _http
          .post(
            Uri.parse('$baseUrl/api/v1/auth/login'),
            headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      String detail;
      try {
        final err = jsonDecode(response.body) as Map<String, dynamic>;
        detail = err['detail']?.toString() ?? 'Erreur inconnue';
      } catch (_) {
        detail = 'Erreur serveur (${response.statusCode})';
      }
      throw ApiException(detail, statusCode: response.statusCode);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Impossible de contacter le serveur : $e');
    }
  }

  // ----------------------------------------------------------------
  // Tokens — stock de bracelets (US 1.4)
  // ----------------------------------------------------------------

  /// POST /api/v1/tokens/init — Enregistre un token dans le stock.
  Future<Map<String, dynamic>> initToken({
    required String tokenUid,
    required String tokenType,
    String? hardwareUid,
  }) async {
    final body = <String, dynamic>{
      'token_uid': tokenUid,
      'token_type': tokenType,
      if (hardwareUid != null) 'hardware_uid': hardwareUid,
    };
    try {
      final uri = Uri.parse('$baseUrl/api/v1/tokens/init');
      final encoded = jsonEncode(body);
      var response = await _http
          .post(uri, headers: _authHeaders, body: encoded)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 401 && await _tryRefresh()) {
        response = await _http
            .post(uri, headers: _authHeaders, body: encoded)
            .timeout(const Duration(seconds: 10));
      }

      if (response.statusCode == 201) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      String detail;
      try {
        final err = jsonDecode(response.body) as Map<String, dynamic>;
        detail = err['detail']?.toString() ?? 'Erreur inconnue';
      } catch (_) {
        detail = 'Erreur serveur (${response.statusCode})';
      }
      throw ApiException(detail, statusCode: response.statusCode);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Impossible de contacter le serveur : $e');
    }
  }

  /// GET /api/v1/tokens — Liste des tokens du stock avec filtres optionnels.
  Future<List<Map<String, dynamic>>> getTokens({
    String? status,
    String? tokenType,
  }) async {
    final params = <String, String>{
      if (status != null) 'status': status,
      if (tokenType != null) 'token_type': tokenType,
    };
    final query = params.entries.map((e) => '${e.key}=${e.value}').join('&');
    final sep = query.isEmpty ? '' : '?$query';
    try {
      final uri = Uri.parse('$baseUrl/api/v1/tokens$sep');
      var response = await _http
          .get(uri, headers: _authHeaders)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 401 && await _tryRefresh()) {
        response = await _http
            .get(uri, headers: _authHeaders)
            .timeout(const Duration(seconds: 10));
      }

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body) as List<dynamic>;
        return data.cast<Map<String, dynamic>>();
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

  /// GET /api/v1/tokens/stats — Statistiques du stock.
  Future<Map<String, dynamic>> getTokenStats() async {
    try {
      final uri = Uri.parse('$baseUrl/api/v1/tokens/stats');
      var response = await _http
          .get(uri, headers: _authHeaders)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 401 && await _tryRefresh()) {
        response = await _http
            .get(uri, headers: _authHeaders)
            .timeout(const Duration(seconds: 10));
      }

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
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
  // Authentification (US 6.1)
  // ----------------------------------------------------------------

  /// POST /api/v1/auth/refresh
  Future<Map<String, dynamic>> refreshToken({required String refreshToken}) async {
    try {
      final response = await _http
          .post(
            Uri.parse('$baseUrl/api/v1/auth/refresh'),
            headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
            body: jsonEncode({'refresh_token': refreshToken}),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      throw ApiException('Refresh token invalide', statusCode: response.statusCode);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Impossible de contacter le serveur : $e');
    }
  }
}
