// Modeles de donnees pour le dashboard de supervision (US 4.2).

class CheckpointSummary {
  final String id;
  final String name;
  final int sequenceOrder;
  final String status;
  final int totalExpected;
  final int totalPresent;
  final double attendanceRate;
  final String? closedAt;

  const CheckpointSummary({
    required this.id,
    required this.name,
    required this.sequenceOrder,
    required this.status,
    required this.totalExpected,
    required this.totalPresent,
    required this.attendanceRate,
    this.closedAt,
  });

  factory CheckpointSummary.fromJson(Map<String, dynamic> json) {
    return CheckpointSummary(
      id: json['id'] as String,
      name: json['name'] as String,
      sequenceOrder: json['sequence_order'] as int,
      status: json['status'] as String,
      totalExpected: json['total_expected'] as int,
      totalPresent: json['total_present'] as int,
      attendanceRate: (json['attendance_rate'] as num).toDouble(),
      closedAt: json['closed_at'] as String?,
    );
  }
}

class DashboardTripSummary {
  final String id;
  final String destination;
  final DateTime date;
  final String status;
  final int totalStudents;
  final int totalPresent;
  final double attendanceRate;
  final int totalCheckpoints;
  final int closedCheckpoints;
  final CheckpointSummary? lastCheckpoint;
  final List<CheckpointSummary> checkpoints;

  const DashboardTripSummary({
    required this.id,
    required this.destination,
    required this.date,
    required this.status,
    required this.totalStudents,
    required this.totalPresent,
    required this.attendanceRate,
    required this.totalCheckpoints,
    required this.closedCheckpoints,
    this.lastCheckpoint,
    required this.checkpoints,
  });

  factory DashboardTripSummary.fromJson(Map<String, dynamic> json) {
    return DashboardTripSummary(
      id: json['id'] as String,
      destination: json['destination'] as String,
      date: DateTime.parse(json['date'] as String),
      status: json['status'] as String,
      totalStudents: json['total_students'] as int,
      totalPresent: json['total_present'] as int,
      attendanceRate: (json['attendance_rate'] as num).toDouble(),
      totalCheckpoints: json['total_checkpoints'] as int,
      closedCheckpoints: json['closed_checkpoints'] as int,
      lastCheckpoint: json['last_checkpoint'] != null
          ? CheckpointSummary.fromJson(json['last_checkpoint'] as Map<String, dynamic>)
          : null,
      checkpoints: (json['checkpoints'] as List)
          .map((e) => CheckpointSummary.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class ScanMethodStats {
  final int nfc;
  final int qrPhysical;
  final int qrDigital;
  final int manual;
  final int total;

  const ScanMethodStats({
    this.nfc = 0,
    this.qrPhysical = 0,
    this.qrDigital = 0,
    this.manual = 0,
    this.total = 0,
  });

  factory ScanMethodStats.fromJson(Map<String, dynamic> json) {
    return ScanMethodStats(
      nfc: json['nfc'] as int,
      qrPhysical: json['qr_physical'] as int,
      qrDigital: json['qr_digital'] as int,
      manual: json['manual'] as int,
      total: json['total'] as int,
    );
  }
}

class DashboardOverview {
  final int totalTrips;
  final int activeTrips;
  final int plannedTrips;
  final int completedTrips;
  final int totalStudents;
  final int totalAttendances;
  final double globalAttendanceRate;
  final ScanMethodStats scanMethodStats;
  final List<DashboardTripSummary> trips;
  final String generatedAt;

  const DashboardOverview({
    required this.totalTrips,
    required this.activeTrips,
    required this.plannedTrips,
    required this.completedTrips,
    required this.totalStudents,
    required this.totalAttendances,
    required this.globalAttendanceRate,
    required this.scanMethodStats,
    required this.trips,
    required this.generatedAt,
  });

  factory DashboardOverview.fromJson(Map<String, dynamic> json) {
    return DashboardOverview(
      totalTrips: json['total_trips'] as int,
      activeTrips: json['active_trips'] as int,
      plannedTrips: json['planned_trips'] as int,
      completedTrips: json['completed_trips'] as int,
      totalStudents: json['total_students'] as int,
      totalAttendances: json['total_attendances'] as int,
      globalAttendanceRate: (json['global_attendance_rate'] as num).toDouble(),
      scanMethodStats: ScanMethodStats.fromJson(json['scan_method_stats'] as Map<String, dynamic>),
      trips: (json['trips'] as List)
          .map((e) => DashboardTripSummary.fromJson(e as Map<String, dynamic>))
          .toList(),
      generatedAt: json['generated_at'] as String,
    );
  }
}
