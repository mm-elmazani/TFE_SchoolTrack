import 'package:flutter/foundation.dart';

import '../../../core/api/api_client.dart';

/// Provider pour la gestion des utilisateurs (Direction uniquement).
class UserProvider extends ChangeNotifier {
  final ApiClient _api = ApiClient();

  List<Map<String, dynamic>> _users = [];
  bool _loading = false;
  String? _error;

  List<Map<String, dynamic>> get users => _users;
  bool get isLoading => _loading;
  String? get error => _error;

  Future<void> loadUsers() async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final data = await _api.getUsers();
      _users = data;
      _loading = false;
      notifyListeners();
    } on ApiException catch (e) {
      _loading = false;
      _error = e.message;
      notifyListeners();
    } catch (e) {
      _loading = false;
      _error = 'Impossible de charger les utilisateurs';
      notifyListeners();
    }
  }

  Future<bool> createUser({
    required String email,
    required String password,
    required String role,
    String? firstName,
    String? lastName,
  }) async {
    try {
      await _api.createUser(
        email: email,
        password: password,
        role: role,
        firstName: firstName,
        lastName: lastName,
      );
      await loadUsers();
      return true;
    } on ApiException catch (e) {
      _error = e.message;
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteUser(String userId) async {
    try {
      await _api.deleteUser(userId);
      await loadUsers();
      return true;
    } on ApiException catch (e) {
      _error = e.message;
      notifyListeners();
      return false;
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
