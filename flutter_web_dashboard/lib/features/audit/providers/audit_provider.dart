import 'package:flutter/foundation.dart';

import '../../../core/api/api_client.dart';

/// Provider pour la consultation des logs d'audit (US 6.4).
/// Gere la pagination, les filtres et le chargement des donnees.
class AuditProvider extends ChangeNotifier {
  final ApiClient _api = ApiClient();

  // Etat
  List<Map<String, dynamic>> _logs = [];
  bool _isLoading = false;
  String? _error;
  int _page = 1;
  int _totalPages = 1;
  int _total = 0;
  final int _pageSize = 50;

  // Filtres actifs
  String? _filterAction;
  String? _filterResourceType;
  String? _filterDateFrom;
  String? _filterDateTo;

  // Getters
  List<Map<String, dynamic>> get logs => _logs;
  bool get isLoading => _isLoading;
  String? get error => _error;
  int get page => _page;
  int get totalPages => _totalPages;
  int get total => _total;
  String? get filterAction => _filterAction;
  String? get filterResourceType => _filterResourceType;
  String? get filterDateFrom => _filterDateFrom;
  String? get filterDateTo => _filterDateTo;

  /// Charge les logs avec les filtres courants.
  Future<void> loadLogs() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final data = await _api.getAuditLogs(
        page: _page,
        pageSize: _pageSize,
        action: _filterAction,
        resourceType: _filterResourceType,
        dateFrom: _filterDateFrom,
        dateTo: _filterDateTo,
      );
      _logs = List<Map<String, dynamic>>.from(data['items'] as List);
      _total = data['total'] as int;
      _totalPages = data['total_pages'] as int;
    } on ApiException catch (e) {
      _error = e.message;
      _logs = [];
    } catch (e) {
      _error = 'Erreur de chargement : $e';
      _logs = [];
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Applique les filtres et recharge depuis la page 1.
  void applyFilters({
    String? action,
    String? resourceType,
    String? dateFrom,
    String? dateTo,
  }) {
    _filterAction = action;
    _filterResourceType = resourceType;
    _filterDateFrom = dateFrom;
    _filterDateTo = dateTo;
    _page = 1;
    loadLogs();
  }

  /// Reinitialise tous les filtres.
  void clearFilters() {
    _filterAction = null;
    _filterResourceType = null;
    _filterDateFrom = null;
    _filterDateTo = null;
    _page = 1;
    loadLogs();
  }

  /// Navigation entre pages.
  void goToPage(int page) {
    if (page < 1 || page > _totalPages) return;
    _page = page;
    loadLogs();
  }

  void nextPage() => goToPage(_page + 1);
  void previousPage() => goToPage(_page - 1);

  /// URL d'export JSON avec les filtres courants.
  String get exportUrl => _api.getAuditExportUrl(
        action: _filterAction,
        resourceType: _filterResourceType,
        dateFrom: _filterDateFrom,
        dateTo: _filterDateTo,
      );
}
