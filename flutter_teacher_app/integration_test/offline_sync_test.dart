/// Tests d'intégration US 7.2 — Scénario offline-first complet.
///
/// Valide automatiquement le flux :
///   téléchargement des données → mode avion → scan de 50 élèves
///   (NFC + QR digital) → reconnexion → synchronisation
///
/// Architecture des tests :
///   - LocalDb RÉEL (SQLite en mémoire via sqflite_common_ffi / natif Android)
///   - ApiClient MOCKÉ (mocktail) — simule réseau online/offline
///   - SyncService RÉEL — orchestre la synchronisation
///
/// Exécution :
///   flutter test integration_test/offline_sync_test.dart
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import 'package:flutter_teacher_app/core/api/api_client.dart';
import 'package:flutter_teacher_app/core/database/local_db.dart';
import 'package:flutter_teacher_app/core/services/sync_service.dart';
import 'package:flutter_teacher_app/features/scan/models/attendance_record.dart';
import 'package:flutter_teacher_app/features/scan/models/checkpoint_create_result.dart';

import 'helpers/test_bundle.dart';

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

/// Crée un [AttendanceRecord] de test.
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
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late MockApiClient mockApi;
  late SyncService syncService;
  late LocalDb db;

  setUpAll(() {
    // Desktop (Windows/Linux/macOS) : FFI requis pour SQLite en mémoire.
    // Android/iOS : sqflite natif est disponible, FFI inutile.
    if (!Platform.isAndroid && !Platform.isIOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
  });

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

        // Vérifier que le bundle est correctement persisté
        final localTrips = await db.getLocalTrips();
        expect(localTrips, hasLength(1));
        expect(localTrips.first.studentCount, equals(50));

        final students = await db.getStudents(_tripId);
        expect(students, hasLength(50));

        final checkpoints = await db.getCheckpoints(_tripId);
        expect(checkpoints, hasLength(1));
        expect(checkpoints.first.id, equals(_checkpointId));

        // ---- 2. Mode avion : API renvoie null (hors-ligne) ----
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
        // 25 NFC_PHYSICAL (students 0-24) + 25 QR_DIGITAL (students 25-49)
        for (var i = 0; i < 50; i++) {
          final method = i < 25 ? ScanMethod.nfcPhysical : ScanMethod.qrDigital;
          await db.saveAttendance(_makeAttendance(
            studentId: 'student-$i',
            scanMethod: method,
            offsetSeconds: i,
          ));
        }

        // Vérifier 50 présences en attente (synced_at IS NULL)
        final pendingAvantSync = await db.getPendingAttendances();
        expect(pendingAvantSync, hasLength(50));

        // ---- 4. Tentative de sync en mode avion → échec attendu ----
        final rapportOffline = await syncService.syncPendingAttendances(
          deviceId: _deviceId,
        );

        expect(rapportOffline.hadNetworkError, isTrue,
            reason: 'Erreur réseau attendue en mode avion');
        expect(rapportOffline.totalFailed, equals(50));

        // Toujours 50 en attente : aucune ne doit être marquée synced
        final pendingApresEchec = await db.getPendingAttendances();
        expect(pendingApresEchec, hasLength(50));

        // ---- 5. Reconnexion : API accepte les 50 présences ----
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

        // ---- 7. Vérification finale : 0 présences en attente ----
        final pendingApresSync = await db.getPendingAttendances();
        expect(pendingApresSync, isEmpty,
            reason: 'Toutes les présences doivent être marquées synced');

        // L'historique de sync enregistre le succès
        final history = await db.getSyncHistory();
        expect(history, isNotEmpty);
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

      // Vérifier l'ordre chronologique strict
      for (var i = 1; i < attendances.length; i++) {
        expect(
          attendances[i].scannedAt.isAfter(attendances[i - 1].scannedAt),
          isTrue,
          reason: 'Présence[$i] doit être postérieure à présence[${i - 1}]',
        );
      }

      // Tous les premiers scans ont scan_sequence = 1
      expect(attendances.every((a) => a.scanSequence == 1), isTrue);
    });

    test('scan_sequence incrémentale sur doublons (même élève, même checkpoint)', () async {
      const studentId = 'student-0';

      // Premier scan → sequence 1
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

      // Deuxième scan (doublon) → sequence 2
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

      expect(seq1, equals(1), reason: 'Premier scan → sequence 1');
      expect(seq2, equals(2), reason: 'Doublon → sequence 2');

      final pending = await db.getPendingAttendances();
      expect(pending, hasLength(2));
      expect(pending.where((a) => a.isDuplicate), hasLength(1),
          reason: 'Un enregistrement doit être marqué comme doublon');
    });

    test('countAttendances retourne le nombre de scans précédents', () async {
      expect(await db.countAttendances(_checkpointId, 'student-0'), equals(0));

      await db.saveAttendance(_makeAttendance(studentId: 'student-0'));
      expect(await db.countAttendances(_checkpointId, 'student-0'), equals(1));

      await db.saveAttendance(_makeAttendance(
        studentId: 'student-0',
        offsetSeconds: 5,
      ));
      expect(await db.countAttendances(_checkpointId, 'student-0'), equals(2));
    });
  });

  // ================================================================
  // Résolution UID → élève (NFC + QR_DIGITAL)
  // ================================================================

  group('US 7.2 — Résolution UID → élève', () {
    setUp(() async {
      await db.saveBundle(makeTestBundle(tripId: _tripId, studentCount: 50));
    });

    test('NFC_PHYSICAL : résolution via student_assignments', () async {
      // NFC-000 est assigné à student-0 (premier de la liste)
      final student = await db.resolveUid('NFC-000', _tripId);

      expect(student, isNotNull);
      expect(student!.id, equals('student-0'));
      expect(student.assignment?.assignmentType, equals('NFC_PHYSICAL'));
      expect(student.assignment?.tokenUid, equals('NFC-000'));
    });

    test('QR_DIGITAL : résolution via student_assignments', () async {
      // QRD-025 est assigné à student-25 (premier QR_DIGITAL, indice 25)
      final student = await db.resolveUid('QRD-025', _tripId);

      expect(student, isNotNull);
      expect(student!.id, equals('student-25'));
      expect(student.assignment?.assignmentType, equals('QR_DIGITAL'));
      expect(student.assignment?.tokenUid, equals('QRD-025'));
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

      expect(nfcResolus, equals(25),
          reason: '25 tokens NFC doivent être résolus');
      expect(qrResolus, equals(25),
          reason: '25 QR digitaux doivent être résolus');
    });
  });

  // ================================================================
  // Checkpoint créé offline (US 3.3)
  // ================================================================

  group('US 7.2 — Checkpoint offline : DRAFT → synced après reconnexion', () {
    test(
      'checkpoint créé hors-ligne est synchronisé au retour du réseau',
      () async {
        await db.saveBundle(makeTestBundle(tripId: _tripId, studentCount: 5));

        // Créer un checkpoint offline (synced_at = NULL → DRAFT)
        final cp = await db.createCheckpoint(
          tripId: _tripId,
          name: 'Arrivée musée',
        );

        expect(cp.status, equals('DRAFT'));

        // Il doit apparaître dans getPendingCheckpoints
        final pendingAvant = await db.getPendingCheckpoints();
        expect(
          pendingAvant.any((row) => row['id'] == cp.id),
          isTrue,
          reason: 'Le checkpoint offline doit être dans la liste pending',
        );

        // Reconnexion : API accepte la création du checkpoint
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

        // Sync : le checkpoint doit être envoyé + marqué synced
        await syncService.syncPendingAttendances(deviceId: _deviceId);

        final pendingApres = await db.getPendingCheckpoints();
        expect(
          pendingApres.any((row) => row['id'] == cp.id),
          isFalse,
          reason: 'Le checkpoint ne doit plus être pending après synchronisation',
        );

        verify(() => mockApi.createCheckpoint(
              _tripId,
              'Arrivée musée',
              clientId: cp.id,
            )).called(1);
      },
    );
  });

  // ================================================================
  // Batch > 500 — chunking SyncService
  // ================================================================

  group('US 7.2 — Batch > 500 (chunking)', () {
    test(
      '600 présences → 2 appels API (500 + 100), toutes marquées synced',
      () async {
        await db.saveBundle(makeTestBundle(tripId: _tripId, studentCount: 50));

        // Insérer 600 présences directement dans SQLite (bypass saveAttendance
        // pour éviter 600 × COUNT queries de scan_sequence)
        final rawDb = await db.database;
        for (var i = 0; i < 600; i++) {
          final studentIdx = i % 50;
          await rawDb.insert('attendances', {
            'id': _uuid.v4(),
            'trip_id': _tripId,
            'checkpoint_id': _checkpointId,
            'student_id': 'student-$studentIdx',
            'scanned_at': DateTime(2026, 6, 15, 9, 0)
                .add(Duration(seconds: i))
                .toIso8601String(),
            'scan_method': ScanMethod.nfcPhysical,
            'scan_sequence': (i ~/ 50) + 1,
            'is_manual': 0,
            'synced_at': null,
          });
        }

        final pending = await db.getPendingAttendances();
        expect(pending, hasLength(600));

        // Mock : API accepte chaque batch et retourne les IDs reçus
        var appelCount = 0;
        when(() => mockApi.syncAttendances(
              scans: any(named: 'scans'),
              deviceId: any(named: 'deviceId'),
            )).thenAnswer((invocation) async {
          final scans =
              invocation.namedArguments[#scans] as List<Map<String, dynamic>>;
          appelCount++;
          final ids =
              scans.map((s) => s['client_uuid'] as String).toList();
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

        // Doit avoir fait 2 appels : batch de 500 + batch de 100
        expect(appelCount, equals(2),
            reason: '600 présences → 2 batches (500 + 100)');

        expect(rapport.totalSent, equals(600));
        expect(rapport.totalAccepted, equals(600));
        expect(rapport.isFullSuccess, isTrue);

        // Toutes marquées synced
        final pendingApres = await db.getPendingAttendances();
        expect(pendingApres, isEmpty,
            reason: 'Aucune présence ne doit rester en attente');
      },
    );
  });
}
