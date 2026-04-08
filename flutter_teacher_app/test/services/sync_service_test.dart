/// Tests unitaires pour SyncService (US 3.1).
///
/// Verifie la synchronisation des presences et checkpoints offline → backend.
/// Utilise mocktail pour mocker ApiClient et LocalDb.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flutter_teacher_app/core/api/api_client.dart';
import 'package:flutter_teacher_app/core/database/local_db.dart';
import 'package:flutter_teacher_app/core/services/sync_service.dart';
import 'package:flutter_teacher_app/features/scan/models/attendance_record.dart';
import 'package:flutter_teacher_app/features/scan/models/checkpoint_create_result.dart';

// ----------------------------------------------------------------
// Mocks
// ----------------------------------------------------------------

class MockApiClient extends Mock implements ApiClient {}

class MockLocalDb extends Mock implements LocalDb {}

// ----------------------------------------------------------------
// Fixtures
// ----------------------------------------------------------------

AttendanceRecord _makeRecord({
  required String id,
  String checkpointId = 'cp-1',
  String tripId = 'trip-1',
  String studentId = 'student-1',
}) {
  return AttendanceRecord(
    id: id,
    checkpointId: checkpointId,
    tripId: tripId,
    studentId: studentId,
    scannedAt: DateTime(2026, 6, 15, 10, 0),
    scanMethod: 'QR_PHYSICAL',
    scanSequence: 1,
    isManual: false,
  );
}

// ----------------------------------------------------------------
// Tests
// ----------------------------------------------------------------

void main() {
  late MockApiClient mockApi;
  late MockLocalDb mockDb;
  late SyncService service;

  setUp(() {
    mockApi = MockApiClient();
    mockDb = MockLocalDb();
    service = SyncService(api: mockApi, db: mockDb);
  });

  // ================================================================
  // SyncReport
  // ================================================================

  group('SyncReport', () {
    test('isFullSuccess — true quand 0 failures et pas de network error', () {
      const report = SyncReport(
        totalSent: 5,
        totalAccepted: 5,
        totalFailed: 0,
        hadNetworkError: false,
      );
      expect(report.isFullSuccess, isTrue);
    });

    test('isFullSuccess — false quand failures > 0', () {
      const report = SyncReport(totalSent: 5, totalFailed: 2);
      expect(report.isFullSuccess, isFalse);
    });

    test('isFullSuccess — false quand hadNetworkError', () {
      const report = SyncReport(totalSent: 5, hadNetworkError: true);
      expect(report.isFullSuccess, isFalse);
    });

    test('nothingToSync — true quand totalSent == 0', () {
      const report = SyncReport();
      expect(report.nothingToSync, isTrue);
    });

    test('nothingToSync — false quand totalSent > 0', () {
      const report = SyncReport(totalSent: 3);
      expect(report.nothingToSync, isFalse);
    });
  });

  // ================================================================
  // syncPendingAttendances
  // ================================================================

  group('SyncService.syncPendingAttendances', () {
    test('aucune pending → rapport vide', () async {
      when(() => mockDb.getPendingCheckpoints())
          .thenAnswer((_) async => []);
      when(() => mockDb.getPendingAttendances())
          .thenAnswer((_) async => []);

      final report = await service.syncPendingAttendances(deviceId: 'dev-1');

      expect(report.nothingToSync, isTrue);
      expect(report.totalSent, 0);
    });

    test('batch succes — marque accepted + duplicate + rejected comme synced', () async {
      final records = [
        _makeRecord(id: 'att-1'),
        _makeRecord(id: 'att-2'),
        _makeRecord(id: 'att-3'),
      ];

      when(() => mockDb.getPendingCheckpoints())
          .thenAnswer((_) async => []);
      when(() => mockDb.getPendingAttendances())
          .thenAnswer((_) async => records);
      when(() => mockApi.syncAttendances(
            scans: any(named: 'scans'),
            deviceId: any(named: 'deviceId'),
          )).thenAnswer((_) async => const SyncResult(
            accepted: ['att-1'],
            duplicate: ['att-2'],
            rejected: ['att-3'],
            totalReceived: 3,
            totalInserted: 1,
          ));
      when(() => mockDb.markAttendancesSynced(any()))
          .thenAnswer((_) async {});
      when(() => mockDb.insertSyncHistory(
            recordsSent: any(named: 'recordsSent'),
            recordsAccepted: any(named: 'recordsAccepted'),
            recordsDuplicate: any(named: 'recordsDuplicate'),
            recordsFailed: any(named: 'recordsFailed'),
            status: any(named: 'status'),
          )).thenAnswer((_) async {});

      final report = await service.syncPendingAttendances(deviceId: 'dev-1');

      expect(report.totalSent, 3);
      expect(report.totalAccepted, 1);
      expect(report.totalDuplicate, 1);
      expect(report.isFullSuccess, isTrue);

      // Verifie que les 3 IDs sont marques comme synced
      verify(() => mockDb.markAttendancesSynced(['att-1', 'att-2', 'att-3']))
          .called(1);
    });

    test('result null → hadNetworkError et arret', () async {
      final records = [_makeRecord(id: 'att-1')];

      when(() => mockDb.getPendingCheckpoints())
          .thenAnswer((_) async => []);
      when(() => mockDb.getPendingAttendances())
          .thenAnswer((_) async => records);
      when(() => mockApi.syncAttendances(
            scans: any(named: 'scans'),
            deviceId: any(named: 'deviceId'),
          )).thenAnswer((_) async => null);
      when(() => mockDb.insertSyncHistory(
            recordsSent: any(named: 'recordsSent'),
            recordsAccepted: any(named: 'recordsAccepted'),
            recordsDuplicate: any(named: 'recordsDuplicate'),
            recordsFailed: any(named: 'recordsFailed'),
            status: any(named: 'status'),
          )).thenAnswer((_) async {});

      final report = await service.syncPendingAttendances(deviceId: 'dev-1');

      expect(report.hadNetworkError, isTrue);
      expect(report.totalFailed, 1);
    });

    test('ApiException — batch echoue mais continue', () async {
      final records = [
        _makeRecord(id: 'att-1'),
      ];

      when(() => mockDb.getPendingCheckpoints())
          .thenAnswer((_) async => []);
      when(() => mockDb.getPendingAttendances())
          .thenAnswer((_) async => records);
      when(() => mockApi.syncAttendances(
            scans: any(named: 'scans'),
            deviceId: any(named: 'deviceId'),
          )).thenThrow(const ApiException('Erreur serveur', statusCode: 422));
      when(() => mockDb.insertSyncHistory(
            recordsSent: any(named: 'recordsSent'),
            recordsAccepted: any(named: 'recordsAccepted'),
            recordsDuplicate: any(named: 'recordsDuplicate'),
            recordsFailed: any(named: 'recordsFailed'),
            status: any(named: 'status'),
          )).thenAnswer((_) async {});

      final report = await service.syncPendingAttendances(deviceId: 'dev-1');

      expect(report.totalFailed, 1);
      expect(report.hadNetworkError, isFalse);
    });

    test('insertSyncHistory appele avec status SUCCESS', () async {
      final records = [_makeRecord(id: 'att-1')];

      when(() => mockDb.getPendingCheckpoints())
          .thenAnswer((_) async => []);
      when(() => mockDb.getPendingAttendances())
          .thenAnswer((_) async => records);
      when(() => mockApi.syncAttendances(
            scans: any(named: 'scans'),
            deviceId: any(named: 'deviceId'),
          )).thenAnswer((_) async => const SyncResult(
            accepted: ['att-1'],
            duplicate: [],
            rejected: [],
            totalReceived: 1,
            totalInserted: 1,
          ));
      when(() => mockDb.markAttendancesSynced(any()))
          .thenAnswer((_) async {});
      when(() => mockDb.insertSyncHistory(
            recordsSent: any(named: 'recordsSent'),
            recordsAccepted: any(named: 'recordsAccepted'),
            recordsDuplicate: any(named: 'recordsDuplicate'),
            recordsFailed: any(named: 'recordsFailed'),
            status: any(named: 'status'),
          )).thenAnswer((_) async {});

      await service.syncPendingAttendances(deviceId: 'dev-1');

      verify(() => mockDb.insertSyncHistory(
            recordsSent: 1,
            recordsAccepted: 1,
            recordsDuplicate: 0,
            recordsFailed: 0,
            status: 'SUCCESS',
          )).called(1);
    });

    test('insertSyncHistory appele avec status OFFLINE quand network error', () async {
      final records = [_makeRecord(id: 'att-1')];

      when(() => mockDb.getPendingCheckpoints())
          .thenAnswer((_) async => []);
      when(() => mockDb.getPendingAttendances())
          .thenAnswer((_) async => records);
      when(() => mockApi.syncAttendances(
            scans: any(named: 'scans'),
            deviceId: any(named: 'deviceId'),
          )).thenAnswer((_) async => null);
      when(() => mockDb.insertSyncHistory(
            recordsSent: any(named: 'recordsSent'),
            recordsAccepted: any(named: 'recordsAccepted'),
            recordsDuplicate: any(named: 'recordsDuplicate'),
            recordsFailed: any(named: 'recordsFailed'),
            status: any(named: 'status'),
          )).thenAnswer((_) async {});

      await service.syncPendingAttendances(deviceId: 'dev-1');

      verify(() => mockDb.insertSyncHistory(
            recordsSent: 1,
            recordsAccepted: 0,
            recordsDuplicate: 0,
            recordsFailed: 1,
            status: 'OFFLINE',
          )).called(1);
    });
  });

  // ================================================================
  // Sync checkpoints offline (US 3.3)
  // ================================================================

  group('SyncService — sync checkpoints', () {
    test('sync checkpoints avant attendances', () async {
      when(() => mockDb.getPendingCheckpoints())
          .thenAnswer((_) async => [
                {'id': 'cp-local-1', 'trip_id': 'trip-1', 'name': 'Depart'},
              ]);
      when(() => mockApi.createCheckpoint('trip-1', 'Depart', clientId: 'cp-local-1'))
          .thenAnswer((_) async => null); // simule un echec reseau
      // Pas d'attendances car checkpoint sync a echoue
      when(() => mockDb.getPendingAttendances())
          .thenAnswer((_) async => []);

      final report = await service.syncPendingAttendances(deviceId: 'dev-1');

      // Le checkpoint n'a pas ete synced (echec reseau)
      verifyNever(() => mockDb.markCheckpointSynced(any()));
      expect(report.nothingToSync, isTrue);
    });

    test('checkpoint sync succes → markCheckpointSynced appele', () async {
      const fakeResult = CheckpointCreateResult(
        serverId: 'cp-server-1',
        sequenceOrder: 1,
      );

      when(() => mockDb.getPendingCheckpoints())
          .thenAnswer((_) async => [
                {'id': 'cp-local-1', 'trip_id': 'trip-1', 'name': 'Depart'},
              ]);
      when(() => mockApi.createCheckpoint('trip-1', 'Depart', clientId: 'cp-local-1'))
          .thenAnswer((_) async => fakeResult);
      when(() => mockDb.markCheckpointSynced('cp-local-1'))
          .thenAnswer((_) async {});
      when(() => mockDb.getPendingAttendances())
          .thenAnswer((_) async => []);

      await service.syncPendingAttendances(deviceId: 'dev-1');

      verify(() => mockDb.markCheckpointSynced('cp-local-1')).called(1);
    });
  });

  // ================================================================
  // getPendingCount
  // ================================================================

  group('SyncService.getPendingCount', () {
    test('retourne le nombre de presences en attente', () async {
      when(() => mockDb.getPendingAttendances())
          .thenAnswer((_) async => [
                _makeRecord(id: 'att-1'),
                _makeRecord(id: 'att-2'),
              ]);

      final count = await service.getPendingCount();

      expect(count, 2);
    });

    test('retourne 0 quand pas de pending', () async {
      when(() => mockDb.getPendingAttendances())
          .thenAnswer((_) async => []);

      final count = await service.getPendingCount();

      expect(count, 0);
    });
  });
}
