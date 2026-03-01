/// Tests unitaires pour ScanProvider — clôture checkpoint (US 2.7).
///
/// Vérifie que checkpointStatus passe à CLOSED après closeCheckpoint(),
/// que LocalDb est bien mis à jour, et que le scanner ne peut plus scanner.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_teacher_app/core/database/local_db.dart';
import 'package:flutter_teacher_app/features/scan/providers/scan_provider.dart';
import 'package:flutter_teacher_app/features/trips/models/offline_bundle.dart';

// ----------------------------------------------------------------
// Fixtures
// ----------------------------------------------------------------

OfflineDataBundle _makeBundle({String checkpointStatus = 'ACTIVE'}) =>
    OfflineDataBundle(
      trip: const OfflineTripInfo(
        id: 'trip-001',
        destination: 'Bruges',
        date: '2026-05-25',
        status: 'ACTIVE',
      ),
      students: const [],
      checkpoints: [
        OfflineCheckpoint(
          id: 'cp-001',
          name: 'Checkpoint test',
          sequenceOrder: 1,
          status: checkpointStatus,
        ),
      ],
      generatedAt: DateTime(2026, 5, 25),
    );

ScanProvider _makeProvider() =>
    ScanProvider(tripId: 'trip-001', checkpointId: 'cp-001');

Future<void> _startSession(ScanProvider provider) async {
  final students = await LocalDb.instance.getStudents('trip-001');
  try {
    await provider.startSession(students);
  } catch (_) {
    // PlatformException NFC ignorée en tests.
  }
}

// ----------------------------------------------------------------
// Setup
// ----------------------------------------------------------------

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  setUp(() {
    LocalDb.testDatabasePath = inMemoryDatabasePath;
  });

  tearDown(() async {
    await LocalDb.instance.closeForTest();
  });

  // ----------------------------------------------------------------
  // closeCheckpoint()
  // ----------------------------------------------------------------

  group('ScanProvider.closeCheckpoint — US 2.7', () {
    test('checkpointStatus passe à CLOSED', () async {
      await LocalDb.instance.saveBundle(_makeBundle(checkpointStatus: 'ACTIVE'));
      final provider = _makeProvider();
      await _startSession(provider);
      expect(provider.checkpointStatus, 'ACTIVE');
      expect(provider.isClosed, isFalse);

      await provider.closeCheckpoint();

      expect(provider.checkpointStatus, 'CLOSED');
      expect(provider.isClosed, isTrue);
      provider.dispose();
    });

    test('SQLite mis à jour : statut CLOSED après clôture', () async {
      await LocalDb.instance.saveBundle(_makeBundle(checkpointStatus: 'ACTIVE'));
      final provider = _makeProvider();
      await _startSession(provider);

      await provider.closeCheckpoint();

      final cp = await LocalDb.instance.getCheckpointById('cp-001');
      expect(cp!.status, 'CLOSED');
      provider.dispose();
    });

    test('isClosed = false avant clôture', () async {
      await LocalDb.instance.saveBundle(_makeBundle(checkpointStatus: 'ACTIVE'));
      final provider = _makeProvider();
      await _startSession(provider);

      expect(provider.isClosed, isFalse);
      provider.dispose();
    });

    test('isClosed = true sur un checkpoint déjà CLOSED au démarrage', () async {
      await LocalDb.instance.saveBundle(_makeBundle(checkpointStatus: 'CLOSED'));
      final provider = _makeProvider();
      await _startSession(provider);

      expect(provider.isClosed, isTrue);
      provider.dispose();
    });
  });
}
