import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../core/api/api_client.dart';

// Modeles inline pour les alertes

class AlertData {
  final String id;
  final String tripId;
  final String? checkpointId;
  final String studentId;
  final String? studentName;
  final String? tripDestination;
  final String? checkpointName;
  final String alertType;
  final String severity;
  final String? message;
  final String status;
  final String? createdAt;
  final String? resolvedAt;

  const AlertData({
    required this.id,
    required this.tripId,
    this.checkpointId,
    required this.studentId,
    this.studentName,
    this.tripDestination,
    this.checkpointName,
    required this.alertType,
    required this.severity,
    this.message,
    required this.status,
    this.createdAt,
    this.resolvedAt,
  });

  factory AlertData.fromJson(Map<String, dynamic> json) {
    return AlertData(
      id: json['id'] as String,
      tripId: json['trip_id'] as String,
      checkpointId: json['checkpoint_id'] as String?,
      studentId: json['student_id'] as String,
      studentName: json['student_name'] as String?,
      tripDestination: json['trip_destination'] as String?,
      checkpointName: json['checkpoint_name'] as String?,
      alertType: json['alert_type'] as String,
      severity: json['severity'] as String,
      message: json['message'] as String?,
      status: json['status'] as String,
      createdAt: json['created_at'] as String?,
      resolvedAt: json['resolved_at'] as String?,
    );
  }
}

class AlertStats {
  final int total;
  final int active;
  final int inProgress;
  final int resolved;
  final int critical;

  const AlertStats({
    this.total = 0,
    this.active = 0,
    this.inProgress = 0,
    this.resolved = 0,
    this.critical = 0,
  });

  factory AlertStats.fromJson(Map<String, dynamic> json) {
    return AlertStats(
      total: json['total'] as int,
      active: json['active'] as int,
      inProgress: json['in_progress'] as int,
      resolved: json['resolved'] as int,
      critical: json['critical'] as int,
    );
  }
}

/// Provider pour les alertes temps reel (US 4.3).
/// Polling toutes les 30 secondes pour les alertes actives.
class AlertProvider extends ChangeNotifier {
  final ApiClient _apiClient;

  AlertProvider({ApiClient? apiClient})
      : _apiClient = apiClient ?? ApiClient();

  List<AlertData> _alerts = [];
  AlertStats _stats = const AlertStats();
  bool _isLoading = false;
  String? _error;
  String _statusFilter = 'ACTIVE';
  Timer? _pollTimer;

  // Getters
  List<AlertData> get alerts => _alerts;
  AlertStats get stats => _stats;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String get statusFilter => _statusFilter;

  void setStatusFilter(String status) {
    _statusFilter = status;
    loadAlerts();
  }

  Future<void> loadAlerts() async {
    _isLoading = _alerts.isEmpty;
    _error = null;
    notifyListeners();

    try {
      final filter = _statusFilter == 'ALL' ? null : _statusFilter;
      final data = await _apiClient.getAlerts(status: filter);
      _alerts = data.map((e) => AlertData.fromJson(e)).toList();

      final statsData = await _apiClient.getAlertStats();
      _stats = AlertStats.fromJson(statsData);

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

  Future<bool> updateStatus(String alertId, String newStatus) async {
    try {
      await _apiClient.updateAlertStatus(alertId, newStatus);
      await loadAlerts();
      return true;
    } on ApiException catch (e) {
      _error = e.message;
      notifyListeners();
      return false;
    }
  }

  void startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      loadAlerts();
    });
  }

  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}
