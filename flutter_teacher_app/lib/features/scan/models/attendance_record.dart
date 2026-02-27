/// Modèle d'une présence enregistrée localement (US 2.2).
/// Correspond au schéma de la table SQLite `attendances`.
library;

/// Méthodes de scan supportées.
class ScanMethod {
  static const String nfcPhysical = 'NFC_PHYSICAL';
  static const String qrPhysical = 'QR_PHYSICAL';
  static const String qrDigital = 'QR_DIGITAL';
  static const String manual = 'MANUAL';
}

/// Présence d'un élève enregistrée hors-ligne.
/// L'id sert de client_uuid pour l'idempotence lors de la synchronisation.
class AttendanceRecord {
  final String id;            // UUID généré côté client
  final String tripId;
  final String checkpointId;
  final String studentId;
  final DateTime scannedAt;
  final String scanMethod;    // ScanMethod.*
  final int scanSequence;     // 1 = premier scan, 2 = doublon, etc.
  final bool isManual;
  final String? justification;
  final String? comment;
  final DateTime? syncedAt;   // null = en attente de sync

  const AttendanceRecord({
    required this.id,
    required this.tripId,
    required this.checkpointId,
    required this.studentId,
    required this.scannedAt,
    required this.scanMethod,
    this.scanSequence = 1,
    this.isManual = false,
    this.justification,
    this.comment,
    this.syncedAt,
  });

  bool get isSynced => syncedAt != null;
  bool get isDuplicate => scanSequence > 1;
}
