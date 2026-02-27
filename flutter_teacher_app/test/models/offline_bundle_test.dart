/// Tests unitaires pour les modèles du bundle offline (US 2.1).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_teacher_app/features/trips/models/offline_bundle.dart';

// ----------------------------------------------------------------
// Fixtures JSON
// ----------------------------------------------------------------

const _tripInfoJson = {
  'id': 'trip-abc',
  'destination': 'Musée du Louvre',
  'date': '2026-06-20',
  'description': 'Sortie culturelle 6ème',
  'status': 'PLANNED',
};

const _assignmentJson = {
  'token_uid': 'AA:BB:CC:DD',
  'assignment_type': 'NFC_PHYSICAL',
};

const _studentWithAssignmentJson = {
  'id': 'student-001',
  'first_name': 'Jean',
  'last_name': 'Dupont',
  'assignment': _assignmentJson,
};

const _studentWithoutAssignmentJson = {
  'id': 'student-002',
  'first_name': 'Marie',
  'last_name': 'Martin',
  'assignment': null,
};

const _checkpointJson = {
  'id': 'cp-001',
  'name': 'Entrée musée',
  'sequence_order': 1,
  'status': 'DRAFT',
};

// ----------------------------------------------------------------
// Tests
// ----------------------------------------------------------------

void main() {
  group('OfflineAssignment.fromJson', () {
    test('parse token_uid et assignment_type', () {
      final a = OfflineAssignment.fromJson(_assignmentJson);
      expect(a.tokenUid, 'AA:BB:CC:DD');
      expect(a.assignmentType, 'NFC_PHYSICAL');
    });

    test('parse QR_DIGITAL', () {
      final a = OfflineAssignment.fromJson({
        'token_uid': 'QRD-XYZ789',
        'assignment_type': 'QR_DIGITAL',
      });
      expect(a.assignmentType, 'QR_DIGITAL');
    });
  });

  group('OfflineStudent.fromJson', () {
    test('parse élève avec assignation NFC', () {
      final s = OfflineStudent.fromJson(_studentWithAssignmentJson);
      expect(s.id, 'student-001');
      expect(s.firstName, 'Jean');
      expect(s.lastName, 'Dupont');
      expect(s.assignment, isNotNull);
      expect(s.assignment!.tokenUid, 'AA:BB:CC:DD');
    });

    test('parse élève sans assignation (null)', () {
      final s = OfflineStudent.fromJson(_studentWithoutAssignmentJson);
      expect(s.assignment, isNull);
    });

    test('fullName retourne "NOM Prénom"', () {
      final s = OfflineStudent.fromJson(_studentWithAssignmentJson);
      expect(s.fullName, 'Dupont Jean');
    });
  });

  group('OfflineCheckpoint.fromJson', () {
    test('parse tous les champs', () {
      final cp = OfflineCheckpoint.fromJson(_checkpointJson);
      expect(cp.id, 'cp-001');
      expect(cp.name, 'Entrée musée');
      expect(cp.sequenceOrder, 1);
      expect(cp.status, 'DRAFT');
    });
  });

  group('OfflineTripInfo.fromJson', () {
    test('parse avec description', () {
      final t = OfflineTripInfo.fromJson(_tripInfoJson);
      expect(t.id, 'trip-abc');
      expect(t.destination, 'Musée du Louvre');
      expect(t.date, '2026-06-20');
      expect(t.description, 'Sortie culturelle 6ème');
      expect(t.status, 'PLANNED');
    });

    test('description peut être null', () {
      final t = OfflineTripInfo.fromJson({
        'id': 'trip-x',
        'destination': 'Test',
        'date': '2026-01-01',
        'description': null,
        'status': 'PLANNED',
      });
      expect(t.description, isNull);
    });
  });

  group('OfflineDataBundle.fromJson', () {
    test('parse un bundle complet', () {
      final bundle = OfflineDataBundle.fromJson({
        'trip': _tripInfoJson,
        'students': [_studentWithAssignmentJson, _studentWithoutAssignmentJson],
        'checkpoints': [_checkpointJson],
        'generated_at': '2026-06-20T08:00:00',
      });

      expect(bundle.trip.destination, 'Musée du Louvre');
      expect(bundle.students.length, 2);
      expect(bundle.checkpoints.length, 1);
      expect(bundle.generatedAt, DateTime(2026, 6, 20, 8, 0, 0));
    });

    test('parse un bundle sans élèves ni checkpoints', () {
      final bundle = OfflineDataBundle.fromJson({
        'trip': _tripInfoJson,
        'students': [],
        'checkpoints': [],
        'generated_at': '2026-06-20T08:00:00',
      });

      expect(bundle.students, isEmpty);
      expect(bundle.checkpoints, isEmpty);
    });
  });
}
