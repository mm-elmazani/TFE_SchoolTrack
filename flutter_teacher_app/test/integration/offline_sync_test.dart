/// Tests d'intégration US 7.2 — Scénario offline-first complet.
///
/// Valide le flux complet :
///   téléchargement bundle → mode avion → scan 50 élèves
///   (25 NFC + 25 QR digital) → reconnexion → synchronisation réussie
///
/// Architecture :
///   - LocalDb RÉEL   — SQLite en mémoire via sqflite_common_ffi (pas de chiffrement)
///   - ApiClient MOCKÉ — simule réseau online / offline (mocktail)
///   - SyncService RÉEL — orchestre la synchronisation
///
/// Exécution sans émulateur :
///   flutter test test/integration/offline_sync_test.dart
///
/// Exécution sur émulateur Android/iOS :
///   flutter test integration_test/offline_sync_test.dart -d <device-id>
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import 'package:flutter_teacher_app/core/api/api_client.dart';
import 'package:flutter_teacher_app/core/database/local_db.dart';
import 'package:flutter_teacher_app/core/services/sync_service.dart';
import 'package:flutter_teacher_app/features/scan/models/attendance_record.dart';
import 'package:flutter_teacher_app/features/scan/models/checkpoint_create_result.dart';

// helpers partagés avec integration_test/
import '../../integration_test/helpers/test_bundle.dart';

// ----------------------------------------------------------------
// Mock
// ----------------------------------------------------------------

class MockApiClient extends Mock implements ApiClient {}

// ----------------------------------------------------------------
// Utilitaires
// ----------------------------------------------------------------

const _uuid = Uuid();
const _tripId = 'trip-test-1';
const _checkpointId = 'cp-server-1';
const _deviceId = 'device-integration-test';

AttendanceRecord _makeAttendance({
  required String studentId,
  String checkpointId = _checkpointId,
  String tripId = _tripId,
  String scanMethod = ScanMethod.nfcPhysical,
  int offsetSeconds = 0,
}) {
  return AttendanceRecord(
    id: _uuid.v4(),
    tripId: tripId,
    checkpointId: checkpointId,
    studentId: studentId,
    scannedAt: DateTime(2026, 6, 15, 9, 0).add(Duration(seconds: offsetSeconds)),
    scanMethod: scanMethod,
    scanSequence: 1,
    isManual: false,
  );
}

// ----------------------------------------------------------------
// Main
// ----------------------------------------------------------------

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late MockApiClient mockApi;
  late SyncService syncService;
  late LocalDb db;

  setUp(() {
    LocalDb.testDatabasePath = inMemoryDatabasePath;
    mockApi = MockApiClient();
    db = LocalDb.instance;
    syncService = SyncService(api: mockApi, db: db);
  });

  tearDown(() async {
    await LocalDb.instance.closeForTest();
  });

  // ================================================================
  // Scénario principal US 7.2
  // ================================================================

  group('US 7.2 — Scénario offline-first complet', () {
    test(
      'download → mode avion → scan 50 élèves → reconnexion → sync réussi',
      () async {
        // ---- 1. Téléchargement du bundle (API → SQLite) ----
        final bundle = makeTestBundle(tripId: _tripId, studentCount: 50);
        await db.saveBundle(bundle);

        final localTrips = await db.getLocalTrips();
        expect(localTrips, hasLength(1));
        expect(localTrips.first.studentCount, equals(50));

        final students = await db.getStudents(_tripId);
        expect(students, hasLength(50));

        final checkpoints = await db.getCheckpoints(_tripId);
        expect(checkpoints, hasLength(1));
        expect(checkpoints.first.id, equals(_checkpointId));

        // ---- 2. Mode avion : API renvoie null ----
        when(() => mockApi.syncAttendances(
              scans: any(named: 'scans'),
              deviceId: any(named: 'deviceId'),
            )).thenAnswer((_) async => null);

        when(() => mockApi.createCheckpoint(
              any(),
              any(),
              clientId: any(named: 'clientId'),
            )).thenAnswer((_) async => null);

        // ---- 3. Scan de 50 élèves hors-ligne ----
        // 25 NFC_PHYSICAL (students 0–24) + 25 QR_DIGITAL (students 25–49)
        for (var i = 0; i < 50; i++) {
          final method = i < 25 ? ScanMethod.nfcPhysical : ScanMethod.qrDigital;
          await db.saveAttendance(_makeAttendance(
            studentId: 'student-$i',
            scanMethod: method,
            offsetSeconds: i,
          ));
        }

        final pendingAvantSync = await db.getPendingAttendances();
        expect(pendingAvantSync, hasLength(50));

        // ---- 4. Sync en mode avion → échec attendu ----
        final rapportOffline = await syncService.syncPendingAttendances(
          deviceId: _deviceId,
        );

        expect(rapportOffline.hadNetworkError, isTrue);
        expect(rapportOffline.totalFailed, equals(50));

        // Toujours 50 en attente
        final pendingApresEchec = await db.getPendingAttendances();
        expect(pendingApresEchec, hasLength(50));

        // ---- 5. Reconnexion : API accepte les 50 ----
        final allIds = pendingApresEchec.map((r) => r.id).toList();
        when(() => mockApi.syncAttendances(
              scans: any(named: 'scans'),
              deviceId: any(named: 'deviceId'),
            )).thenAnswer((_) async => SyncResult(
              accepted: allIds,
              duplicate: [],
              rejected: [],
              totalReceived: 50,
              totalInserted: 50,
            ));

        // ---- 6. Synchronisation réussie ----
        final rapportSync = await syncService.syncPendingAttendances(
          deviceId: _deviceId,
        );

        expect(rapportSync.totalSent, equals(50));
        expect(rapportSync.totalAccepted, equals(50));
        expect(rapportSync.totalDuplicate, equals(0));
        expect(rapportSync.totalFailed, equals(0));
        expect(rapportSync.hadNetworkError, isFalse);
        expect(rapportSync.isFullSuccess, isTrue);

        // ---- 7. 0 présences en attente ----
        final pendingApresSync = await db.getPendingAttendances();
        expect(pendingApresSync, isEmpty);

        final history = await db.getSyncHistory();
        expect(history.first.status, equals('SUCCESS'));
        expect(history.first.recordsSent, equals(50));
        expect(history.first.recordsAccepted, equals(50));
      },
    );
  });

  // ================================================================
  // Intégrité des données locales
  // ================================================================

  group('US 7.2 — Intégrité des données locales', () {
    setUp(() async {
      await db.saveBundle(makeTestBundle(tripId: _tripId, studentCount: 10));
    });

    test('ordre des scans préservé (scanned_at ASC)', () async {
      final base = DateTime(2026, 6, 15, 9, 0);

      for (var i = 0; i < 10; i++) {
        await db.saveAttendance(AttendanceRecord(
          id: _uuid.v4(),
          tripId: _tripId,
          checkpointId: _checkpointId,
          studentId: 'student-$i',
          scannedAt: base.add(Duration(seconds: i * 30)),
          scanMethod: ScanMethod.nfcPhysical,
          scanSequence: 1,
          isManual: false,
        ));
      }

      final attendances = await db.getAttendancesByCheckpoint(_checkpointId);
      expect(attendances, hasLength(10));

      for (var i = 1; i < attendances.length; i++) {
        expect(
          attendances[i].scannedAt.isAfter(attendances[i - 1].scannedAt),
          isTrue,
        );
      }
      expect(attendances.every((a) => a.scanSequence == 1), isTrue);
    });

    test('scan_sequence incrémentale sur doublons', () async {
      const studentId = 'student-0';

      final seq1 = await db.saveAttendance(AttendanceRecord(
        id: _uuid.v4(),
        tripId: _tripId,
        checkpointId: _checkpointId,
        studentId: studentId,
        scannedAt: DateTime(2026, 6, 15, 9, 0),
        scanMethod: ScanMethod.nfcPhysical,
        scanSequence: 1,
        isManual: false,
      ));

      final seq2 = await db.saveAttendance(AttendanceRecord(
        id: _uuid.v4(),
        tripId: _tripId,
        checkpointId: _checkpointId,
        studentId: studentId,
        scannedAt: DateTime(2026, 6, 15, 9, 5),
        scanMethod: ScanMethod.nfcPhysical,
        scanSequence: 1,
        isManual: false,
      ));

      expect(seq1, equals(1));
      expect(seq2, equals(2));

      final pending = await db.getPendingAttendances();
      expect(pending, hasLength(2));
      expect(pending.where((a) => a.isDuplicate), hasLength(1));
    });

    test('countAttendances retourne le nombre de scans précédents', () async {
      expect(await db.countAttendances(_checkpointId, 'student-0'), equals(0));

      await db.saveAttendance(_makeAttendance(studentId: 'student-0'));
      expect(await db.countAttendances(_checkpointId, 'student-0'), equals(1));

      await db.saveAttendance(
          _makeAttendance(studentId: 'student-0', offsetSeconds: 5));
      expect(await db.countAttendances(_checkpointId, 'student-0'), equals(2));
    });
  });

  // ================================================================
  // Résolution UID → élève
  // ================================================================

  group('US 7.2 — Résolution UID → élève', () {
    setUp(() async {
      await db.saveBundle(makeTestBundle(tripId: _tripId, studentCount: 50));
    });

    test('NFC_PHYSICAL : résolution via student_assignments', () async {
      final student = await db.resolveUid('NFC-000', _tripId);
      expect(student, isNotNull);
      expect(student!.id, equals('student-0'));
      expect(student.assignment?.assignmentType, equals('NFC_PHYSICAL'));
    });

    test('QR_DIGITAL : résolution via student_assignments', () async {
      final student = await db.resolveUid('QRD-025', _tripId);
      expect(student, isNotNull);
      expect(student!.id, equals('student-25'));
      expect(student.assignment?.assignmentType, equals('QR_DIGITAL'));
    });

    test('UID inconnu → null', () async {
      final student = await db.resolveUid('INCONNU-999', _tripId);
      expect(student, isNull);
    });

    test('resolveStudentById → retourne le bon élève', () async {
      final student = await db.resolveStudentById('student-10', _tripId);
      expect(student, isNotNull);
      expect(student!.firstName, equals('Prénom10'));
      expect(student.lastName, equals('Nom10'));
    });

    test('25 tokens NFC et 25 QR_DIGITAL tous résolus correctement', () async {
      var nfcResolus = 0;
      var qrResolus = 0;

      for (var i = 0; i < 25; i++) {
        final uid = 'NFC-${i.toString().padLeft(3, '0')}';
        final s = await db.resolveUid(uid, _tripId);
        if (s != null && s.assignment?.assignmentType == 'NFC_PHYSICAL') {
          nfcResolus++;
        }
      }

      for (var i = 25; i < 50; i++) {
        final uid = 'QRD-${i.toString().padLeft(3, '0')}';
        final s = await db.resolveUid(uid, _tripId);
        if (s != null && s.assignment?.assignmentType == 'QR_DIGITAL') {
          qrResolus++;
        }
      }

      expect(nfcResolus, equals(25));
      expect(qrResolus, equals(25));
    });
  });

  // ================================================================
  // Checkpoint offline (US 3.3)
  // ================================================================

  group('US 7.2 — Checkpoint offline : DRAFT → synced après reconnexion', () {
    test('checkpoint créé hors-ligne est synchronisé au retour du réseau', () async {
      await db.saveBundle(makeTestBundle(tripId: _tripId, studentCount: 5));

      final cp = await db.createCheckpoint(
        tripId: _tripId,
        name: 'Arrivée musée',
      );

      expect(cp.status, equals('DRAFT'));

      final pendingAvant = await db.getPendingCheckpoints();
      expect(pendingAvant.any((row) => row['id'] == cp.id), isTrue);

      when(() => mockApi.createCheckpoint(
            any(),
            any(),
            clientId: any(named: 'clientId'),
          )).thenAnswer((_) async => const CheckpointCreateResult(
            serverId: 'cp-server-nouveau',
            sequenceOrder: 2,
          ));

      when(() => mockApi.syncAttendances(
            scans: any(named: 'scans'),
            deviceId: any(named: 'deviceId'),
          )).thenAnswer((_) async => const SyncResult(
            accepted: [],
            duplicate: [],
            rejected: [],
            totalReceived: 0,
            totalInserted: 0,
          ));

      await syncService.syncPendingAttendances(deviceId: _deviceId);

      final pendingApres = await db.getPendingCheckpoints();
      expect(pendingApres.any((row) => row['id'] == cp.id), isFalse);

      verify(() => mockApi.createCheckpoint(
            _tripId,
            'Arrivée musée',
            clientId: cp.id,
          )).called(1);
    });
  });

  // ================================================================
  // Batch > 500 — chunking SyncService
  // ================================================================

  group('US 7.2 — Batch > 500 (chunking)', () {
    test('600 présences → 2 appels API (500 + 100), toutes marquées synced', () async {
      await db.saveBundle(makeTestBundle(tripId: _tripId, studentCount: 50));

      // Insertion directe pour éviter 600 × COUNT (scan_sequence)
      final rawDb = await db.database;
      for (var i = 0; i < 600; i++) {
        await rawDb.insert('attendances', {
          'id': _uuid.v4(),
          'trip_id': _tripId,
          'checkpoint_id': _checkpointId,
          'student_id': 'student-${i % 50}',
          'scanned_at': DateTime(2026, 6, 15, 9, 0)
              .add(Duration(seconds: i))
              .toIso8601String(),
          'scan_method': ScanMethod.nfcPhysical,
          'scan_sequence': (i ~/ 50) + 1,
          'is_manual': 0,
          'synced_at': null,
        });
      }

      expect(await db.getPendingAttendances(), hasLength(600));

      var appelCount = 0;
      when(() => mockApi.syncAttendances(
            scans: any(named: 'scans'),
            deviceId: any(named: 'deviceId'),
          )).thenAnswer((invocation) async {
        final scans = invocation.namedArguments[#scans] as List<Map<String, dynamic>>;
        appelCount++;
        final ids = scans.map((s) => s['client_uuid'] as String).toList();
        return SyncResult(
          accepted: ids,
          duplicate: [],
          rejected: [],
          totalReceived: ids.length,
          totalInserted: ids.length,
        );
      });

      when(() => mockApi.createCheckpoint(
            any(),
            any(),
            clientId: any(named: 'clientId'),
          )).thenAnswer((_) async => null);

      final rapport = await syncService.syncPendingAttendances(
        deviceId: _deviceId,
      );

      expect(appelCount, equals(2), reason: '600 présences → 2 batches (500 + 100)');
      expect(rapport.totalSent, equals(600));
      expect(rapport.totalAccepted, equals(600));
      expect(rapport.isFullSuccess, isTrue);

      expect(await db.getPendingAttendances(), isEmpty);
    });
  });
}
