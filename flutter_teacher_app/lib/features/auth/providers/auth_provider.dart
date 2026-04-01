import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/api/api_client.dart';

/// Etat d'authentification de l'app enseignants.
/// Tokens JWT stockes dans flutter_secure_storage (Android Keystore).
class AuthProvider extends ChangeNotifier {
  static const _keyAccessToken = 'access_token';
  static const _keyRefreshToken = 'refresh_token';
  static const _keyUserEmail = 'user_email';
  static const _keyUserRole = 'user_role';
  static const _keyUserFirstName = 'user_first_name';
  static const _keyUserLastName = 'user_last_name';

  final FlutterSecureStorage _storage;
  final ApiClient _api;

  String? _accessToken;
  String? _refreshToken;
  String? _userEmail;
  String? _userRole;
  String? _userFirstName;
  String? _userLastName;
  bool _loading = false;
  String? _error;
  bool _initialized = false;

  AuthProvider({FlutterSecureStorage? storage, ApiClient? api})
      : _storage = storage ?? const FlutterSecureStorage(),
        _api = api ?? ApiClient();

  // Getters
  bool get isAuthenticated => _accessToken != null;
  bool get isLoading => _loading;
  bool get isInitialized => _initialized;
  String? get error => _error;
  String? get accessToken => _accessToken;
  String? get userEmail => _userEmail;
  String? get userRole => _userRole;
  String? get userDisplayName {
    if (_userFirstName != null && _userLastName != null) {
      return '$_userFirstName $_userLastName';
    }
    return _userEmail;
  }

  /// Roles avec droits d'administration.
  bool get isAdmin =>
      _userRole == 'DIRECTION' || _userRole == 'ADMIN_TECH';

  /// Roles avec acces aux actions terrain (scan, checkpoints, sync).
  bool get isFieldUser =>
      _userRole == 'DIRECTION' || _userRole == 'ADMIN_TECH' || _userRole == 'TEACHER';

  /// Charge les tokens depuis le stockage securise au demarrage.
  Future<void> init() async {
    _accessToken = await _storage.read(key: _keyAccessToken);
    _refreshToken = await _storage.read(key: _keyRefreshToken);
    _userEmail = await _storage.read(key: _keyUserEmail);
    _userRole = await _storage.read(key: _keyUserRole);
    _userFirstName = await _storage.read(key: _keyUserFirstName);
    _userLastName = await _storage.read(key: _keyUserLastName);
    ApiClient.authToken = _accessToken;
    ApiClient.onTokenExpired = refreshTokens;
    _initialized = true;
    notifyListeners();
  }

  /// Connexion avec email + mot de passe (+ code TOTP optionnel + ecole).
  Future<bool> login(String email, String password, {String? totpCode, String? schoolSlug}) async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final data = await _api.login(
        email: email,
        password: password,
        totpCode: totpCode,
        schoolSlug: schoolSlug,
      );

      _accessToken = data['access_token'] as String;
      _refreshToken = data['refresh_token'] as String;

      final user = data['user'] as Map<String, dynamic>;
      _userEmail = user['email'] as String?;
      _userRole = user['role'] as String?;
      _userFirstName = user['first_name'] as String?;
      _userLastName = user['last_name'] as String?;

      ApiClient.authToken = _accessToken;
      await _persistTokens();
      _loading = false;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      _loading = false;
      if (e.statusCode == 400 && e.message.contains('2FA')) {
        _error = '2FA_REQUIRED';
      } else {
        _error = e.message;
      }
      notifyListeners();
      return false;
    } catch (e) {
      _loading = false;
      _error = 'Impossible de contacter le serveur';
      notifyListeners();
      return false;
    }
  }

  /// Deconnexion : supprime les tokens.
  Future<void> logout() async {
    ApiClient.authToken = null;
    _accessToken = null;
    _refreshToken = null;
    _userEmail = null;
    _userRole = null;
    _userFirstName = null;
    _userLastName = null;
    _error = null;
    await _storage.deleteAll();
    notifyListeners();
  }

  /// Rafraichit l'access token via le refresh token.
  Future<bool> refreshTokens() async {
    if (_refreshToken == null) return false;
    try {
      final data = await _api.refreshToken(refreshToken: _refreshToken!);
      _accessToken = data['access_token'] as String;
      _refreshToken = data['refresh_token'] as String;
      ApiClient.authToken = _accessToken;
      await _persistTokens();
      notifyListeners();
      return true;
    } catch (_) {
      await logout();
      return false;
    }
  }

  Future<void> _persistTokens() async {
    if (_accessToken != null) await _storage.write(key: _keyAccessToken, value: _accessToken!);
    if (_refreshToken != null) await _storage.write(key: _keyRefreshToken, value: _refreshToken!);
    if (_userEmail != null) await _storage.write(key: _keyUserEmail, value: _userEmail!);
    if (_userRole != null) await _storage.write(key: _keyUserRole, value: _userRole!);
    if (_userFirstName != null) await _storage.write(key: _keyUserFirstName, value: _userFirstName!);
    if (_userLastName != null) await _storage.write(key: _keyUserLastName, value: _userLastName!);
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
