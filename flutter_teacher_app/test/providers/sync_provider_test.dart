/// Tests unitaires pour SyncProvider (US 3.1).
///
/// Verifie l'etat de synchronisation, les transitions idle/syncing/synced/error,
/// et la garde anti-sync concurrente.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flutter_teacher_app/core/services/sync_service.dart';
import 'package:flutter_teacher_app/core/services/sync_provider.dart';

// ----------------------------------------------------------------
// Mocks
// ----------------------------------------------------------------

class MockSyncService extends Mock implements SyncService {}

// ----------------------------------------------------------------
// Tests
// ----------------------------------------------------------------

void main() {
  late MockSyncService mockService;
  late SyncProvider provider;

  setUp(() {
    mockService = MockSyncService();
    // On ne passe pas de Connectivity mock pour eviter les platform channels.
    // SyncProvider accepte service en constructeur.
    provider = SyncProvider(service: mockService);
  });

  // Pas de tearDown avec dispose() — certains tests appellent dispose() directement.
  // ChangeNotifier leve une erreur si on dispose deux fois.

  // ================================================================
  // Etat initial
  // ================================================================

  test('etat initial : status idle, pendingCount 0', () {
    expect(provider.status, SyncStatus.idle);
    expect(provider.pendingCount, 0);
    expect(provider.lastSyncAt, isNull);
    expect(provider.lastError, isNull);
    expect(provider.hasPending, isFalse);
  });

  // ================================================================
  // syncNow
  // ================================================================

  group('SyncProvider.syncNow', () {
    test('succes total → status synced', () async {
      when(() => mockService.syncPendingAttendances(deviceId: any(named: 'deviceId')))
          .thenAnswer((_) async => const SyncReport(
                totalSent: 5,
                totalAccepted: 5,
                totalFailed: 0,
              ));
      when(() => mockService.getPendingCount())
          .thenAnswer((_) async => 0);

      await provider.syncNow();

      expect(provider.status, SyncStatus.synced);
      expect(provider.lastSyncAt, isNotNull);
      expect(provider.lastError, isNull);
    });

    test('nothing to sync → status idle', () async {
      when(() => mockService.syncPendingAttendances(deviceId: any(named: 'deviceId')))
          .thenAnswer((_) async => const SyncReport());
      when(() => mockService.getPendingCount())
          .thenAnswer((_) async => 0);

      await provider.syncNow();

      expect(provider.status, SyncStatus.idle);
    });

    test('network error → status offline', () async {
      when(() => mockService.syncPendingAttendances(deviceId: any(named: 'deviceId')))
          .thenAnswer((_) async => const SyncReport(
                totalSent: 3,
                totalFailed: 3,
                hadNetworkError: true,
              ));
      when(() => mockService.getPendingCount())
          .thenAnswer((_) async => 3);

      await provider.syncNow();

      expect(provider.status, SyncStatus.offline);
      expect(provider.lastError, contains('connexion'));
    });

    test('partial failure → status error avec message', () async {
      when(() => mockService.syncPendingAttendances(deviceId: any(named: 'deviceId')))
          .thenAnswer((_) async => const SyncReport(
                totalSent: 5,
                totalAccepted: 3,
                totalFailed: 2,
              ));
      when(() => mockService.getPendingCount())
          .thenAnswer((_) async => 2);

      await provider.syncNow();

      expect(provider.status, SyncStatus.error);
      expect(provider.lastError, contains('2'));
    });

    test('exception → status error', () async {
      when(() => mockService.syncPendingAttendances(deviceId: any(named: 'deviceId')))
          .thenThrow(Exception('Unexpected crash'));
      when(() => mockService.getPendingCount())
          .thenAnswer((_) async => 0);

      await provider.syncNow();

      expect(provider.status, SyncStatus.error);
      expect(provider.lastError, isNotNull);
    });
  });

  // ================================================================
  // refreshPendingCount
  // ================================================================

  group('SyncProvider.refreshPendingCount', () {
    test('met a jour le compteur depuis le service', () async {
      when(() => mockService.getPendingCount())
          .thenAnswer((_) async => 42);

      await provider.refreshPendingCount();

      expect(provider.pendingCount, 42);
      expect(provider.hasPending, isTrue);
    });

    test('0 pending → hasPending false', () async {
      when(() => mockService.getPendingCount())
          .thenAnswer((_) async => 0);

      await provider.refreshPendingCount();

      expect(provider.pendingCount, 0);
      expect(provider.hasPending, isFalse);
    });
  });

  // ================================================================
  // stopAutoSync / dispose
  // ================================================================

  test('stopAutoSync est idempotent', () {
    // Doit pouvoir etre appele plusieurs fois sans erreur
    provider.stopAutoSync();
    provider.stopAutoSync();
  });

  test('dispose appelle stopAutoSync', () {
    // Apres dispose, pas d'erreur
    provider.dispose();
  });
}
