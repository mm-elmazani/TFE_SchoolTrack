import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../core/api/api_client.dart';
import '../models/dashboard_models.dart';

/// Provider pour le dashboard de supervision (US 4.2).
/// Gere le chargement des stats et l'auto-refresh toutes les 60 secondes.
class DashboardProvider extends ChangeNotifier {
  final ApiClient _apiClient;

  DashboardProvider({ApiClient? apiClient})
      : _apiClient = apiClient ?? ApiClient();

  // --- Etat ---
  DashboardOverview? _overview;
  bool _isLoading = false;
  String? _error;
  String _statusFilter = 'ALL';
  Timer? _refreshTimer;

  // --- Getters ---
  DashboardOverview? get overview => _overview;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String get statusFilter => _statusFilter;

  // --- Filtres ---
  void setStatusFilter(String status) {
    _statusFilter = status;
    loadOverview();
  }

  /// Charge les donnees du dashboard depuis l'API.
  Future<void> loadOverview() async {
    _isLoading = _overview == null; // Spinner uniquement au premier chargement
    _error = null;
    notifyListeners();

    try {
      final filter = _statusFilter == 'ALL' ? null : _statusFilter;
      final data = await _apiClient.getDashboardOverview(status: filter);
      _overview = DashboardOverview.fromJson(data);
      _isLoading = false;
    } on ApiException catch (e) {
      _error = e.message;
      _isLoading = false;
    } catch (e) {
      _error = 'Erreur inattendue : $e';
      _isLoading = false;
    }

    notifyListeners();
  }

  /// Demarre l'auto-refresh toutes les 60 secondes.
  void startAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      loadOverview();
    });
  }

  /// Arrete l'auto-refresh.
  void stopAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }
}
