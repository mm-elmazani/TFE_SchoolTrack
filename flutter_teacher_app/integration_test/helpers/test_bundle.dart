/// Fixtures pour les tests d'intégration US 7.2.
///
/// Génère un bundle offline avec N élèves :
/// - La première moitié : assignation NFC_PHYSICAL (uid = NFC-XXX)
/// - La seconde moitié  : assignation QR_DIGITAL  (uid = QRD-XXX)
///
/// Un checkpoint ACTIVE est inclus (déjà synchronisé depuis le serveur).
library;

import 'package:flutter_teacher_app/features/trips/models/offline_bundle.dart';

/// Crée un [OfflineDataBundle] de test avec [studentCount] élèves.
///
/// [tripId]       — identifiant du voyage (défaut : 'trip-test-1')
/// [studentCount] — nombre d'élèves à générer (défaut : 50)
OfflineDataBundle makeTestBundle({
  String tripId = 'trip-test-1',
  int studentCount = 50,
}) {
  final half = studentCount ~/ 2;

  final students = List.generate(studentCount, (i) {
    final isNfc = i < half;
    final uid = isNfc
        ? 'NFC-${i.toString().padLeft(3, '0')}'
        : 'QRD-${i.toString().padLeft(3, '0')}';
    final type = isNfc ? 'NFC_PHYSICAL' : 'QR_DIGITAL';

    final assignment = OfflineAssignment(tokenUid: uid, assignmentType: type);

    return OfflineStudent(
      id: 'student-$i',
      firstName: 'Prénom$i',
      lastName: 'Nom$i',
      className: 'Classe${i % 3 + 1}',
      assignment: assignment,
      assignments: [assignment],
    );
  });

  return OfflineDataBundle(
    trip: OfflineTripInfo(
      id: tripId,
      destination: 'Paris — Test Intégration',
      date: '2026-06-15',
      status: 'ACTIVE',
      studentCount: studentCount,
      classes: ['Classe1', 'Classe2', 'Classe3'],
    ),
    students: students,
    checkpoints: const [
      OfflineCheckpoint(
        id: 'cp-server-1',
        name: 'Départ école',
        sequenceOrder: 1,
        status: 'ACTIVE',
      ),
    ],
    generatedAt: DateTime(2026, 6, 15, 8, 0),
  );
}
