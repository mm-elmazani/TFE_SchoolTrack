/// Tests unitaires pour les méthodes attendance de LocalDb (US 2.2).
/// Utilise sqflite_common_ffi avec base en mémoire pour isoler chaque test.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_teacher_app/core/database/local_db.dart';
import 'package:flutter_teacher_app/features/scan/models/attendance_record.dart';
import 'package:flutter_teacher_app/features/trips/models/offline_bundle.dart';

// ----------------------------------------------------------------
// Fixtures
// ----------------------------------------------------------------

OfflineDataBundle _makeBundle({String tripId = 'trip-001'}) =>
    OfflineDataBundle(
      trip: OfflineTripInfo(
        id: tripId,
        destination: 'Paris',
        date: '2026-06-15',
        status: 'PLANNED',
      ),
      students: const [
        OfflineStudent(
          id: 'student-001',
          firstName: 'Jean',
          lastName: 'Dupont',
          assignment: OfflineAssignment(
            tokenUid: 'AA:BB:CC:DD',
            assignmentType: 'NFC_PHYSICAL',
          ),
        ),
        OfflineStudent(
          id: 'student-002',
          firstName: 'Marie',
          lastName: 'Martin',
        ),
      ],
      checkpoints: const [
        OfflineCheckpoint(
          id: 'cp-001',
          name: 'Entrée',
          sequenceOrder: 1,
          status: 'ACTIVE',
        ),
      ],
      generatedAt: DateTime(2026, 6, 15, 8, 0),
    );

AttendanceRecord _makeAtt({
  String id = 'att-001',
  String tripId = 'trip-001',
  String checkpointId = 'cp-001',
  String studentId = 'student-001',
  String scanMethod = ScanMethod.nfcPhysical,
}) =>
    AttendanceRecord(
      id: id,
      tripId: tripId,
      checkpointId: checkpointId,
      studentId: studentId,
      scannedAt: DateTime(2026, 6, 15, 10, 0),
      scanMethod: scanMethod,
    );

// ----------------------------------------------------------------
// Setup
// ----------------------------------------------------------------

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
    LocalDb.testDatabasePath = inMemoryDatabasePath;
  });

  tearDown(() async {
    await LocalDb.instance.closeForTest();
  });

  // ----------------------------------------------------------------
  // resolveUid
  // ----------------------------------------------------------------

  group('LocalDb.resolveUid', () {
    test('retourne l\'élève si l\'UID correspond', () async {
      await LocalDb.instance.saveBundle(_makeBundle());

      final student =
          await LocalDb.instance.resolveUid('AA:BB:CC:DD', 'trip-001');
      expect(student, isNotNull);
      expect(student!.id, 'student-001');
      expect(student.firstName, 'Jean');
      expect(student.lastName, 'Dupont');
    });

    test('retourne null si l\'UID est inconnu', () async {
      await LocalDb.instance.saveBundle(_makeBundle());

      final student =
          await LocalDb.instance.resolveUid('FF:FF:FF:FF', 'trip-001');
      expect(student, isNull);
    });

    test('retourne null si l\'UID appartient à un autre voyage', () async {
      await LocalDb.instance.saveBundle(_makeBundle(tripId: 'trip-001'));

      final student =
          await LocalDb.instance.resolveUid('AA:BB:CC:DD', 'trip-002');
      expect(student, isNull);
    });

    test('retourne null si aucun élève n\'a ce token', () async {
      await LocalDb.instance.saveBundle(_makeBundle());

      // student-002 n'a pas de token_uid
      final student =
          await LocalDb.instance.resolveUid('00:00:00:00', 'trip-001');
      expect(student, isNull);
    });
  });

  // ----------------------------------------------------------------
  // saveAttendance
  // ----------------------------------------------------------------

  group('LocalDb.saveAttendance', () {
    test('retourne séquence 1 pour le premier scan', () async {
      final seq = await LocalDb.instance.saveAttendance(_makeAtt());
      expect(seq, 1);
    });

    test('retourne séquence 2 pour le deuxième scan du même élève', () async {
      await LocalDb.instance.saveAttendance(_makeAtt(id: 'att-001'));
      final seq =
          await LocalDb.instance.saveAttendance(_makeAtt(id: 'att-002'));
      expect(seq, 2);
    });

    test('séquences indépendantes pour des checkpoints différents', () async {
      await LocalDb.instance
          .saveAttendance(_makeAtt(id: 'att-1', checkpointId: 'cp-001'));
      final seq = await LocalDb.instance
          .saveAttendance(_makeAtt(id: 'att-2', checkpointId: 'cp-002'));
      expect(seq, 1);
    });

    test('sauvegarde tous les champs correctement', () async {
      final record = AttendanceRecord(
        id: 'uuid-test',
        tripId: 'trip-001',
        checkpointId: 'cp-001',
        studentId: 'student-001',
        scannedAt: DateTime(2026, 6, 15, 10, 30, 0),
        scanMethod: ScanMethod.qrDigital,
        isManual: false,
      );
      await LocalDb.instance.saveAttendance(record);

      final atts =
          await LocalDb.instance.getAttendancesByCheckpoint('cp-001');
      expect(atts.length, 1);
      expect(atts[0].id, 'uuid-test');
      expect(atts[0].scanMethod, ScanMethod.qrDigital);
      expect(atts[0].syncedAt, isNull);
      expect(atts[0].isManual, isFalse);
    });
  });

  // ----------------------------------------------------------------
  // countAttendances
  // ----------------------------------------------------------------

  group('LocalDb.countAttendances', () {
    test('retourne 0 si aucune présence', () async {
      final count =
          await LocalDb.instance.countAttendances('cp-001', 'student-001');
      expect(count, 0);
    });

    test('retourne le nombre correct après plusieurs scans', () async {
      await LocalDb.instance.saveAttendance(_makeAtt(id: 'a1'));
      await LocalDb.instance.saveAttendance(_makeAtt(id: 'a2'));
      await LocalDb.instance.saveAttendance(_makeAtt(id: 'a3'));

      final count =
          await LocalDb.instance.countAttendances('cp-001', 'student-001');
      expect(count, 3);
    });

    test('ne compte pas les scans d\'un autre élève', () async {
      await LocalDb.instance
          .saveAttendance(_makeAtt(id: 'a1', studentId: 'student-001'));
      await LocalDb.instance
          .saveAttendance(_makeAtt(id: 'a2', studentId: 'student-002'));

      final count =
          await LocalDb.instance.countAttendances('cp-001', 'student-001');
      expect(count, 1);
    });
  });

  // ----------------------------------------------------------------
  // getAttendancesByCheckpoint
  // ----------------------------------------------------------------

  group('LocalDb.getAttendancesByCheckpoint', () {
    test('retourne liste vide si aucune présence', () async {
      final atts =
          await LocalDb.instance.getAttendancesByCheckpoint('cp-vide');
      expect(atts, isEmpty);
    });

    test('ne retourne que les présences du checkpoint demandé', () async {
      await LocalDb.instance
          .saveAttendance(_makeAtt(id: 'att-cp1', checkpointId: 'cp-001'));
      await LocalDb.instance
          .saveAttendance(_makeAtt(id: 'att-cp2', checkpointId: 'cp-002'));

      final atts =
          await LocalDb.instance.getAttendancesByCheckpoint('cp-001');
      expect(atts.length, 1);
      expect(atts[0].id, 'att-cp1');
    });

    test('retourne les présences triées par scanned_at', () async {
      await LocalDb.instance
          .saveAttendance(_makeAtt(id: 'att-b', studentId: 'student-002'));
      await LocalDb.instance
          .saveAttendance(_makeAtt(id: 'att-a', studentId: 'student-001'));

      // Forcer des timestamps distincts
      final db = await LocalDb.instance.database;
      await db.update('attendances', {'scanned_at': '2026-06-15T10:00:00.000'},
          where: 'id = ?', whereArgs: ['att-a']);
      await db.update('attendances', {'scanned_at': '2026-06-15T11:00:00.000'},
          where: 'id = ?', whereArgs: ['att-b']);

      final atts =
          await LocalDb.instance.getAttendancesByCheckpoint('cp-001');
      expect(atts[0].id, 'att-a');
      expect(atts[1].id, 'att-b');
    });
  });

  // ----------------------------------------------------------------
  // getPendingAttendances / markAttendancesSynced
  // ----------------------------------------------------------------

  group('LocalDb.getPendingAttendances', () {
    test('retourne uniquement les non-synchronisées', () async {
      await LocalDb.instance.saveAttendance(_makeAtt(id: 'att-pending'));
      await LocalDb.instance.saveAttendance(_makeAtt(id: 'att-synced'));
      await LocalDb.instance.markAttendancesSynced(['att-synced']);

      final pending = await LocalDb.instance.getPendingAttendances();
      expect(pending.length, 1);
      expect(pending[0].id, 'att-pending');
    });

    test('retourne liste vide si tout est synchronisé', () async {
      await LocalDb.instance.saveAttendance(_makeAtt(id: 'att-1'));
      await LocalDb.instance.markAttendancesSynced(['att-1']);

      final pending = await LocalDb.instance.getPendingAttendances();
      expect(pending, isEmpty);
    });
  });

  group('LocalDb.markAttendancesSynced', () {
    test('met à jour synced_at pour tous les IDs donnés', () async {
      await LocalDb.instance.saveAttendance(_makeAtt(id: 'att-1'));
      await LocalDb.instance.saveAttendance(_makeAtt(id: 'att-2'));
      await LocalDb.instance.markAttendancesSynced(['att-1', 'att-2']);

      final pending = await LocalDb.instance.getPendingAttendances();
      expect(pending, isEmpty);
    });

    test('ne fait rien si la liste d\'IDs est vide', () async {
      await LocalDb.instance.saveAttendance(_makeAtt(id: 'att-1'));
      await LocalDb.instance.markAttendancesSynced([]);

      final pending = await LocalDb.instance.getPendingAttendances();
      expect(pending.length, 1);
    });

    test('ne modifie pas les présences non concernées', () async {
      await LocalDb.instance.saveAttendance(_makeAtt(id: 'att-1'));
      await LocalDb.instance.saveAttendance(_makeAtt(id: 'att-2'));
      await LocalDb.instance.markAttendancesSynced(['att-1']);

      final pending = await LocalDb.instance.getPendingAttendances();
      expect(pending.length, 1);
      expect(pending[0].id, 'att-2');
    });
  });
}
