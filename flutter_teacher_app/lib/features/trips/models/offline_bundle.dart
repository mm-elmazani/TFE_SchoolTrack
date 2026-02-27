/// Modèles de données pour le bundle offline (US 2.1).
/// Correspondent aux schémas Pydantic du backend (schemas/offline.py).
library;

// ----------------------------------------------------------------
// Résumé voyage (liste des voyages depuis GET /api/v1/trips)
// ----------------------------------------------------------------

/// Résumé d'un voyage affiché dans la liste de sélection.
class TripSummary {
  final String id;
  final String destination;
  final String date;
  final String status;
  final int studentCount;

  const TripSummary({
    required this.id,
    required this.destination,
    required this.date,
    required this.status,
    required this.studentCount,
  });

  factory TripSummary.fromJson(Map<String, dynamic> j) => TripSummary(
        id: j['id'] as String,
        destination: j['destination'] as String,
        date: j['date'] as String,
        status: j['status'] as String,
        // Le backend renvoie total_students (TripResponse)
        studentCount: j['total_students'] as int? ?? j['student_count'] as int? ?? 0,
      );
}

// ----------------------------------------------------------------
// Bundle offline (GET /api/v1/trips/{trip_id}/offline-data)
// ----------------------------------------------------------------

/// Assignation active d'un élève (bracelet NFC, QR physique ou QR digital).
class OfflineAssignment {
  final String tokenUid;
  final String assignmentType; // NFC_PHYSICAL, QR_PHYSICAL, QR_DIGITAL

  const OfflineAssignment({
    required this.tokenUid,
    required this.assignmentType,
  });

  factory OfflineAssignment.fromJson(Map<String, dynamic> j) =>
      OfflineAssignment(
        tokenUid: j['token_uid'] as String,
        assignmentType: j['assignment_type'] as String,
      );
}

/// Élève avec son assignation de bracelet/QR (null si non assigné).
class OfflineStudent {
  final String id;
  final String firstName;
  final String lastName;
  final OfflineAssignment? assignment;

  const OfflineStudent({
    required this.id,
    required this.firstName,
    required this.lastName,
    this.assignment,
  });

  String get fullName => '$lastName $firstName';

  factory OfflineStudent.fromJson(Map<String, dynamic> j) => OfflineStudent(
        id: j['id'] as String,
        firstName: j['first_name'] as String,
        lastName: j['last_name'] as String,
        assignment: j['assignment'] != null
            ? OfflineAssignment.fromJson(
                j['assignment'] as Map<String, dynamic>)
            : null,
      );
}

/// Point de contrôle existant sur le voyage.
class OfflineCheckpoint {
  final String id;
  final String name;
  final int sequenceOrder;
  final String status; // DRAFT, ACTIVE, CLOSED

  const OfflineCheckpoint({
    required this.id,
    required this.name,
    required this.sequenceOrder,
    required this.status,
  });

  factory OfflineCheckpoint.fromJson(Map<String, dynamic> j) =>
      OfflineCheckpoint(
        id: j['id'] as String,
        name: j['name'] as String,
        sequenceOrder: j['sequence_order'] as int,
        status: j['status'] as String,
      );
}

/// Informations essentielles du voyage pour le mode offline.
class OfflineTripInfo {
  final String id;
  final String destination;
  final String date;
  final String? description;
  final String status;

  const OfflineTripInfo({
    required this.id,
    required this.destination,
    required this.date,
    this.description,
    required this.status,
  });

  factory OfflineTripInfo.fromJson(Map<String, dynamic> j) => OfflineTripInfo(
        id: j['id'] as String,
        destination: j['destination'] as String,
        date: j['date'] as String,
        description: j['description'] as String?,
        status: j['status'] as String,
      );
}

/// Bundle complet téléchargé avant de partir en mode offline.
class OfflineDataBundle {
  final OfflineTripInfo trip;
  final List<OfflineStudent> students;
  final List<OfflineCheckpoint> checkpoints;
  final DateTime generatedAt;

  const OfflineDataBundle({
    required this.trip,
    required this.students,
    required this.checkpoints,
    required this.generatedAt,
  });

  factory OfflineDataBundle.fromJson(Map<String, dynamic> j) =>
      OfflineDataBundle(
        trip: OfflineTripInfo.fromJson(j['trip'] as Map<String, dynamic>),
        students: (j['students'] as List<dynamic>)
            .map((s) => OfflineStudent.fromJson(s as Map<String, dynamic>))
            .toList(),
        checkpoints: (j['checkpoints'] as List<dynamic>)
            .map((c) =>
                OfflineCheckpoint.fromJson(c as Map<String, dynamic>))
            .toList(),
        generatedAt: DateTime.parse(j['generated_at'] as String),
      );
}
