import 'package:flutter/material.dart';
import '../../../core/api/api_client.dart';

// Modele d'une entree timeline
class CheckpointTimelineEntry {
  final String id;
  final String name;
  final String? description;
  final int sequenceOrder;
  final String status;
  final String? createdAt;
  final String? startedAt;
  final String? closedAt;
  final String? createdByName;
  final int scanCount;
  final int studentCount;
  final int? durationMinutes;

  CheckpointTimelineEntry({
    required this.id,
    required this.name,
    this.description,
    required this.sequenceOrder,
    required this.status,
    this.createdAt,
    this.startedAt,
    this.closedAt,
    this.createdByName,
    this.scanCount = 0,
    this.studentCount = 0,
    this.durationMinutes,
  });

  factory CheckpointTimelineEntry.fromJson(Map<String, dynamic> json) {
    return CheckpointTimelineEntry(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      sequenceOrder: json['sequence_order'] as int,
      status: json['status'] as String,
      createdAt: json['created_at'] as String?,
      startedAt: json['started_at'] as String?,
      closedAt: json['closed_at'] as String?,
      createdByName: json['created_by_name'] as String?,
      scanCount: json['scan_count'] as int? ?? 0,
      studentCount: json['student_count'] as int? ?? 0,
      durationMinutes: json['duration_minutes'] as int?,
    );
  }
}

// Resume global
class CheckpointsSummary {
  final String tripId;
  final String tripDestination;
  final int totalCheckpoints;
  final int activeCheckpoints;
  final int closedCheckpoints;
  final int totalScans;
  final double? avgDurationMinutes;
  final List<CheckpointTimelineEntry> timeline;

  CheckpointsSummary({
    required this.tripId,
    required this.tripDestination,
    required this.totalCheckpoints,
    required this.activeCheckpoints,
    required this.closedCheckpoints,
    required this.totalScans,
    this.avgDurationMinutes,
    required this.timeline,
  });

  factory CheckpointsSummary.fromJson(Map<String, dynamic> json) {
    return CheckpointsSummary(
      tripId: json['trip_id'] as String,
      tripDestination: json['trip_destination'] as String,
      totalCheckpoints: json['total_checkpoints'] as int,
      activeCheckpoints: json['active_checkpoints'] as int,
      closedCheckpoints: json['closed_checkpoints'] as int,
      totalScans: json['total_scans'] as int,
      avgDurationMinutes: (json['avg_duration_minutes'] as num?)?.toDouble(),
      timeline: (json['timeline'] as List)
          .map((e) => CheckpointTimelineEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// Provider pour la timeline checkpoints d'un voyage (US 4.4).
class CheckpointTimelineProvider extends ChangeNotifier {
  final ApiClient _api = ApiClient();

  CheckpointsSummary? _summary;
  bool _isLoading = false;
  String? _error;

  CheckpointsSummary? get summary => _summary;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> loadSummary(String tripId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final data = await _api.getCheckpointsSummary(tripId);
      _summary = CheckpointsSummary.fromJson(data);
    } on ApiException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = 'Erreur : $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
