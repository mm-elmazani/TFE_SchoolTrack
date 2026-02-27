/// Tests unitaires pour ScanProvider (US 2.2).
///
/// NFC non testé (dépend du hardware).
/// On teste la logique de state via onQrDetected + LocalDb en mémoire.
/// audioPlayer non injecté → mode silencieux (null), aucun appel platform channel.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_teacher_app/core/database/local_db.dart';
import 'package:flutter_teacher_app/features/scan/providers/scan_provider.dart';
import 'package:flutter_teacher_app/features/trips/models/offline_bundle.dart';

// ----------------------------------------------------------------
// Fixtures
// ----------------------------------------------------------------

OfflineDataBundle _makeBundle() => OfflineDataBundle(
      trip: const OfflineTripInfo(
        id: 'trip-001',
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
          assignment: OfflineAssignment(
            tokenUid: 'BB:BB:BB:BB',
            assignmentType: 'NFC_PHYSICAL',
          ),
        ),
      ],
      checkpoints: const [],
      generatedAt: DateTime(2026, 6, 15),
    );

/// audioPlayer = null → mode silencieux, aucun appel platform channel
ScanProvider _makeProvider() =>
    ScanProvider(tripId: 'trip-001', checkpointId: 'cp-001');

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
  // État initial
  // ----------------------------------------------------------------

  group('ScanProvider — état initial', () {
    test('toutes les valeurs initiales sont correctes', () {
      final provider = _makeProvider();
      expect(provider.state, ScanState.idle);
      expect(provider.presentCount, 0);
      expect(provider.totalStudents, 0);
      expect(provider.missingCount, 0);
      expect(provider.nfcAvailable, isFalse);
      expect(provider.qrPaused, isFalse);
      expect(provider.lastResult, isNull);
      expect(provider.lastError, isNull);
      provider.dispose();
    });
  });

  // ----------------------------------------------------------------
  // onQrDetected — succès
  // ----------------------------------------------------------------

  group('ScanProvider.onQrDetected — succès', () {
    test('passe à success pour un élève reconnu', () async {
      await LocalDb.instance.saveBundle(_makeBundle());
      final provider = _makeProvider();

      await provider.onQrDetected('AA:BB:CC:DD');

      expect(provider.state, ScanState.success);
      expect(provider.lastResult, isNotNull);
      expect(provider.lastResult!.fullName, 'Dupont Jean');
      expect(provider.lastResult!.isDuplicate, isFalse);
      expect(provider.lastError, isNull);
      provider.dispose();
    });

    test('incrémente presentCount après premier scan', () async {
      await LocalDb.instance.saveBundle(_makeBundle());
      final provider = _makeProvider();

      expect(provider.presentCount, 0);
      await provider.onQrDetected('AA:BB:CC:DD');
      expect(provider.presentCount, 1);
      provider.dispose();
    });

    test('deux élèves distincts incrémentent chacun presentCount', () async {
      await LocalDb.instance.saveBundle(_makeBundle());
      final provider = _makeProvider();

      await provider.onQrDetected('AA:BB:CC:DD');
      provider.resumeScanning();
      await provider.onQrDetected('BB:BB:BB:BB');

      expect(provider.presentCount, 2);
      provider.dispose();
    });
  });

  // ----------------------------------------------------------------
  // onQrDetected — doublon
  // ----------------------------------------------------------------

  group('ScanProvider.onQrDetected — doublon', () {
    test('passe à duplicate pour un élève déjà scanné', () async {
      await LocalDb.instance.saveBundle(_makeBundle());
      final provider = _makeProvider();

      await provider.onQrDetected('AA:BB:CC:DD');
      provider.resumeScanning();
      await provider.onQrDetected('AA:BB:CC:DD');

      expect(provider.state, ScanState.duplicate);
      expect(provider.lastResult!.isDuplicate, isTrue);
      provider.dispose();
    });

    test('ne pas incrémenter presentCount pour un doublon', () async {
      await LocalDb.instance.saveBundle(_makeBundle());
      final provider = _makeProvider();

      await provider.onQrDetected('AA:BB:CC:DD');
      expect(provider.presentCount, 1);
      provider.resumeScanning();
      await provider.onQrDetected('AA:BB:CC:DD');
      expect(provider.presentCount, 1);
      provider.dispose();
    });
  });

  // ----------------------------------------------------------------
  // onQrDetected — erreur
  // ----------------------------------------------------------------

  group('ScanProvider.onQrDetected — erreur', () {
    test('passe à error pour un UID inconnu', () async {
      await LocalDb.instance.saveBundle(_makeBundle());
      final provider = _makeProvider();

      await provider.onQrDetected('FF:FF:FF:FF');

      expect(provider.state, ScanState.error);
      expect(provider.lastError, isNotNull);
      expect(provider.lastResult, isNull);
      provider.dispose();
    });

    test('passe à error pour un QR vide', () async {
      final provider = _makeProvider();

      await provider.onQrDetected('');

      expect(provider.state, ScanState.error);
      provider.dispose();
    });
  });

  // ----------------------------------------------------------------
  // Guard qrPaused
  // ----------------------------------------------------------------

  group('ScanProvider — garde qrPaused', () {
    test('ignore le scan suivant si qrPaused est true', () async {
      await LocalDb.instance.saveBundle(_makeBundle());
      final provider = _makeProvider();

      await provider.onQrDetected('AA:BB:CC:DD'); // success + qrPaused = true
      expect(provider.qrPaused, isTrue);

      await provider.onQrDetected('BB:BB:BB:BB'); // ignoré
      expect(provider.presentCount, 1);
      provider.dispose();
    });
  });

  // ----------------------------------------------------------------
  // resumeScanning
  // ----------------------------------------------------------------

  group('ScanProvider.resumeScanning', () {
    test('remet l\'état à idle et efface les résultats', () async {
      await LocalDb.instance.saveBundle(_makeBundle());
      final provider = _makeProvider();

      await provider.onQrDetected('AA:BB:CC:DD');
      expect(provider.state, ScanState.success);

      provider.resumeScanning();

      expect(provider.state, ScanState.idle);
      expect(provider.qrPaused, isFalse);
      expect(provider.lastResult, isNull);
      expect(provider.lastError, isNull);
      provider.dispose();
    });

    test('permet de scanner à nouveau après resumeScanning', () async {
      await LocalDb.instance.saveBundle(_makeBundle());
      final provider = _makeProvider();

      await provider.onQrDetected('AA:BB:CC:DD');
      provider.resumeScanning();
      await provider.onQrDetected('BB:BB:BB:BB');

      expect(provider.state, ScanState.success);
      expect(provider.lastResult!.fullName, 'Martin Marie');
      provider.dispose();
    });
  });

  // ----------------------------------------------------------------
  // missingCount
  // ----------------------------------------------------------------

  group('ScanProvider.missingCount', () {
    test('missingCount = totalStudents - presentCount', () {
      final provider = _makeProvider();
      expect(provider.missingCount,
          provider.totalStudents - provider.presentCount);
      provider.dispose();
    });
  });
}
