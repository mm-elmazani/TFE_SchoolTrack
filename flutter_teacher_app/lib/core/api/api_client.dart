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
    String name, {
    String? clientId,
  }) async {
    try {
      final body = <String, dynamic>{'name': name};
      if (clientId != null) body['id'] = clientId;
      final response = await _http
          .post(
            Uri.parse('$baseUrl/api/v1/trips/$tripId/checkpoints'),
            headers: _authHeaders,
            body: jsonEncode(body),
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

  // ----------------------------------------------------------------
  // Photos élèves
  // ----------------------------------------------------------------

  /// Télécharge la photo d'un élève (endpoint protégé).
  /// Retourne les bytes de l'image, ou null si aucune photo ou erreur réseau.
  Future<List<int>?> getStudentPhoto(String studentId) async {
    try {
      final uri = Uri.parse('$baseUrl/api/v1/students/$studentId/photo');
      var response = await _http
          .get(uri, headers: _authHeaders)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 401 && await _tryRefresh()) {
        response = await _http
            .get(uri, headers: _authHeaders)
            .timeout(const Duration(seconds: 10));
      }

      if (response.statusCode == 200) return response.bodyBytes;
      return null;
    } catch (_) {
      return null;
    }
  }

  // ----------------------------------------------------------------
  // Ecoles (public)
  // ----------------------------------------------------------------

  /// GET /api/v1/schools/public — Liste des ecoles actives (sans auth).
  Future<List<Map<String, dynamic>>> getSchoolsPublic() async {
    try {
      final response = await _http
          .get(
            Uri.parse('$baseUrl/api/v1/schools/public'),
            headers: {'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 10));

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

  /// POST /api/v1/auth/login
  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
    String? totpCode,
    String? schoolSlug,
  }) async {
    final body = <String, dynamic>{
      'email': email,
      'password': password,
      if (totpCode != null && totpCode.isNotEmpty) 'totp_code': totpCode,
      if (schoolSlug != null && schoolSlug.isNotEmpty) 'school_slug': schoolSlug,
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

  /// GET /api/v1/tokens/next-sequence — Prochain numero de sequence disponible.
  Future<int> getNextSequence({String prefix = 'ST'}) async {
    try {
      final uri = Uri.parse('$baseUrl/api/v1/tokens/next-sequence?prefix=$prefix');
      var response = await _http
          .get(uri, headers: _authHeaders)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 401 && await _tryRefresh()) {
        response = await _http
            .get(uri, headers: _authHeaders)
            .timeout(const Duration(seconds: 10));
      }

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return data['next_sequence'] as int;
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
  // Synchronisation offline → online (US 3.1)
  // ----------------------------------------------------------------

  /// POST /api/sync/attendances — Envoie un batch de presences au backend.
  ///
  /// Retourne la reponse parsee (accepted/duplicate) ou null si hors-ligne.
  /// Le [deviceId] identifie l'appareil pour les logs de sync.
  Future<SyncResult?> syncAttendances({
    required List<Map<String, dynamic>> scans,
    required String deviceId,
  }) async {
    if (scans.isEmpty) {
      return SyncResult(accepted: [], duplicate: [], rejected: [], totalReceived: 0, totalInserted: 0);
    }
    try {
      final body = jsonEncode({'scans': scans, 'device_id': deviceId});
      final uri = Uri.parse('$baseUrl/api/sync/attendances');
      var response = await _http
          .post(uri, headers: _authHeaders, body: body)
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 401 && await _tryRefresh()) {
        response = await _http
            .post(uri, headers: _authHeaders, body: body)
            .timeout(const Duration(seconds: 30));
      }

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return SyncResult.fromJson(data);
      }
      // Erreur de validation (422) → throw pour que le SyncService puisse reagir
      if (response.statusCode == 422) {
        throw ApiException('Batch invalide', statusCode: 422);
      }
      return null;
    } on ApiException {
      rethrow;
    } catch (_) {
      // Hors-ligne ou erreur reseau → retourne null (mode offline)
      return null;
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

/// Reponse du backend apres synchronisation (POST /api/sync/attendances).
class SyncResult {
  final List<String> accepted;
  final List<String> duplicate;
  final List<String> rejected;
  final int totalReceived;
  final int totalInserted;

  const SyncResult({
    required this.accepted,
    required this.duplicate,
    required this.rejected,
    required this.totalReceived,
    required this.totalInserted,
  });

  factory SyncResult.fromJson(Map<String, dynamic> json) {
    return SyncResult(
      accepted: (json['accepted'] as List<dynamic>).cast<String>(),
      duplicate: (json['duplicate'] as List<dynamic>).cast<String>(),
      rejected: (json['rejected'] as List<dynamic>?)?.cast<String>() ?? [],
      totalReceived: json['total_received'] as int,
      totalInserted: json['total_inserted'] as int,
    );
  }
}
