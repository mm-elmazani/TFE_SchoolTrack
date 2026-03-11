import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/api/api_client.dart';

/// Etat d'authentification global du dashboard.
/// Stocke les tokens JWT dans localStorage (via shared_preferences).
class AuthProvider extends ChangeNotifier {
  static const _keyAccessToken = 'access_token';
  static const _keyRefreshToken = 'refresh_token';
  static const _keyUserEmail = 'user_email';
  static const _keyUserRole = 'user_role';
  static const _keyUserFirstName = 'user_first_name';
  static const _keyUserLastName = 'user_last_name';

  final ApiClient _api = ApiClient();

  String? _accessToken;
  String? _refreshToken;
  String? _userEmail;
  String? _userRole;
  String? _userFirstName;
  String? _userLastName;
  bool _loading = false;
  String? _error;
  bool _initialized = false;

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

  /// Roles avec droits d'administration (ecriture) sur le dashboard.
  bool get isAdmin =>
      _userRole == 'DIRECTION' || _userRole == 'ADMIN_TECH';

  /// Roles avec acces aux actions terrain (scan, checkpoints, sync).
  bool get isFieldUser =>
      _userRole == 'DIRECTION' || _userRole == 'ADMIN_TECH' || _userRole == 'TEACHER';

  /// Role observateur = lecture seule uniquement.
  bool get isObserver => _userRole == 'OBSERVER';

  /// Charge les tokens depuis le stockage local au demarrage.
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _accessToken = prefs.getString(_keyAccessToken);
    _refreshToken = prefs.getString(_keyRefreshToken);
    _userEmail = prefs.getString(_keyUserEmail);
    _userRole = prefs.getString(_keyUserRole);
    _userFirstName = prefs.getString(_keyUserFirstName);
    _userLastName = prefs.getString(_keyUserLastName);
    ApiClient.authToken = _accessToken;
    ApiClient.onTokenExpired = refreshTokens;
    _initialized = true;
    notifyListeners();
  }

  /// Connexion avec email + mot de passe (+ code TOTP optionnel).
  Future<bool> login(String email, String password, {String? totpCode}) async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final data = await _api.login(
        email: email,
        password: password,
        totpCode: totpCode,
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

  /// Deconnexion : supprime les tokens locaux.
  Future<void> logout() async {
    ApiClient.authToken = null;
    _accessToken = null;
    _refreshToken = null;
    _userEmail = null;
    _userRole = null;
    _userFirstName = null;
    _userLastName = null;
    _error = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyAccessToken);
    await prefs.remove(_keyRefreshToken);
    await prefs.remove(_keyUserEmail);
    await prefs.remove(_keyUserRole);
    await prefs.remove(_keyUserFirstName);
    await prefs.remove(_keyUserLastName);

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
    final prefs = await SharedPreferences.getInstance();
    if (_accessToken != null) await prefs.setString(_keyAccessToken, _accessToken!);
    if (_refreshToken != null) await prefs.setString(_keyRefreshToken, _refreshToken!);
    if (_userEmail != null) await prefs.setString(_keyUserEmail, _userEmail!);
    if (_userRole != null) await prefs.setString(_keyUserRole, _userRole!);
    if (_userFirstName != null) await prefs.setString(_keyUserFirstName, _userFirstName!);
    if (_userLastName != null) await prefs.setString(_keyUserLastName, _userLastName!);
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
