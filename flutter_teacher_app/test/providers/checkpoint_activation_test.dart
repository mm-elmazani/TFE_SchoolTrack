/// Tests unitaires pour ScanProvider — transition DRAFT→ACTIVE (US 2.5).
///
/// Vérifie que checkpointStatus passe à ACTIVE au premier scan réussi
/// non-doublon, et que LocalDb.activateCheckpoint() est persisté.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_teacher_app/core/database/local_db.dart';
import 'package:flutter_teacher_app/features/scan/models/attendance_record.dart';
import 'package:flutter_teacher_app/features/scan/providers/scan_provider.dart';
import 'package:flutter_teacher_app/features/trips/models/offline_bundle.dart';

// ----------------------------------------------------------------
// Fixtures
// ----------------------------------------------------------------

OfflineDataBundle _makeBundle({String checkpointStatus = 'DRAFT'}) =>
    OfflineDataBundle(
      trip: const OfflineTripInfo(
        id: 'trip-001',
        destination: 'Gand',
        date: '2026-05-25',
        status: 'ACTIVE',
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
      ],
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

Future<void> _startSession(
  ScanProvider provider,
  List<OfflineStudent> students,
) async {
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
  // startSession() — chargement du statut initial du checkpoint
  // ----------------------------------------------------------------

  group('ScanProvider.checkpointStatus — chargement initial', () {
    test('statut DRAFT chargé depuis SQLite au démarrage', () async {
      await LocalDb.instance.saveBundle(_makeBundle(checkpointStatus: 'DRAFT'));
      final students = await LocalDb.instance.getStudents('trip-001');
      final provider = _makeProvider();

      await _startSession(provider, students);

      expect(provider.checkpointStatus, 'DRAFT');
      provider.dispose();
    });

    test('statut ACTIVE chargé depuis SQLite au démarrage', () async {
      await LocalDb.instance.saveBundle(_makeBundle(checkpointStatus: 'ACTIVE'));
      final students = await LocalDb.instance.getStudents('trip-001');
      final provider = _makeProvider();

      await _startSession(provider, students);

      expect(provider.checkpointStatus, 'ACTIVE');
      provider.dispose();
    });

    test('statut défaut ACTIVE si checkpoint introuvable en SQLite', () async {
      // Provider pour un checkpoint qui n'existe pas en SQLite
      final provider = ScanProvider(
        tripId: 'trip-999',
        checkpointId: 'cp-inconnu',
      );
      try {
        await provider.startSession([]);
      } catch (_) {}

      // Défaut sécurisé = ACTIVE (ne bloque pas le scan)
      expect(provider.checkpointStatus, 'ACTIVE');
      provider.dispose();
    });
  });

  // ----------------------------------------------------------------
  // Transition DRAFT→ACTIVE au 1er scan réussi
  // ----------------------------------------------------------------

  group('ScanProvider — transition DRAFT→ACTIVE', () {
    test('checkpointStatus passe à ACTIVE après premier scan', () async {
      await LocalDb.instance.saveBundle(_makeBundle(checkpointStatus: 'DRAFT'));
      final students = await LocalDb.instance.getStudents('trip-001');
      final provider = _makeProvider();
      await _startSession(provider, students);
      expect(provider.checkpointStatus, 'DRAFT');

      await provider.onQrDetected('AA:BB:CC:DD');

      expect(provider.checkpointStatus, 'ACTIVE');
      provider.dispose();
    });

    test('SQLite mis à jour : statut ACTIVE après premier scan', () async {
      await LocalDb.instance.saveBundle(_makeBundle(checkpointStatus: 'DRAFT'));
      final students = await LocalDb.instance.getStudents('trip-001');
      final provider = _makeProvider();
      await _startSession(provider, students);

      await provider.onQrDetected('AA:BB:CC:DD');

      // Vérification dans SQLite
      final cp = await LocalDb.instance.getCheckpointById('cp-001');
      expect(cp!.status, 'ACTIVE');
      provider.dispose();
    });

    test('statut reste ACTIVE sur scans suivants (pas de double activation)', () async {
      await LocalDb.instance.saveBundle(_makeBundle(checkpointStatus: 'DRAFT'));
      final students = await LocalDb.instance.getStudents('trip-001');
      final provider = _makeProvider();
      await _startSession(provider, students);

      await provider.onQrDetected('AA:BB:CC:DD'); // 1er scan → ACTIVE
      provider.resumeScanning();
      await provider.onQrDetected('AA:BB:CC:DD'); // doublon

      expect(provider.checkpointStatus, 'ACTIVE');
      provider.dispose();
    });

    test('doublon seul ne déclenche pas la transition DRAFT→ACTIVE', () async {
      await LocalDb.instance.saveBundle(_makeBundle(checkpointStatus: 'DRAFT'));
      final students = await LocalDb.instance.getStudents('trip-001');

      // Insérer une présence préexistante pour que le scan suivant soit un doublon
      await LocalDb.instance.saveAttendance(AttendanceRecord(
        id: 'att-pre',
        tripId: 'trip-001',
        checkpointId: 'cp-001',
        studentId: 'student-001',
        scannedAt: DateTime(2026, 5, 25, 8, 0),
        scanMethod: ScanMethod.qrPhysical,
        scanSequence: 1,
        isManual: false,
      ));

      final provider = _makeProvider();
      await _startSession(provider, students);
      // Student-001 est déjà dans presentMap → le scan sera un doublon
      await provider.onQrDetected('AA:BB:CC:DD');

      // Un doublon ne doit PAS activer le checkpoint
      final cp = await LocalDb.instance.getCheckpointById('cp-001');
      expect(cp!.status, 'DRAFT');
      provider.dispose();
    });

    test('checkpoint déjà ACTIVE : pas de re-activation', () async {
      await LocalDb.instance.saveBundle(_makeBundle(checkpointStatus: 'ACTIVE'));
      final students = await LocalDb.instance.getStudents('trip-001');
      final provider = _makeProvider();
      await _startSession(provider, students);
      expect(provider.checkpointStatus, 'ACTIVE');

      await provider.onQrDetected('AA:BB:CC:DD');

      expect(provider.checkpointStatus, 'ACTIVE');
      provider.dispose();
    });

    test('markManually() sur checkpoint DRAFT déclenche aussi la transition', () async {
      await LocalDb.instance.saveBundle(_makeBundle(checkpointStatus: 'DRAFT'));
      final students = await LocalDb.instance.getStudents('trip-001');
      final provider = _makeProvider();
      await _startSession(provider, students);
      expect(provider.checkpointStatus, 'DRAFT');

      const student = OfflineStudent(
        id: 'student-001',
        firstName: 'Jean',
        lastName: 'Dupont',
      );
      await provider.markManually(
        student: student,
        justification: 'BADGE_MISSING',
      );

      expect(provider.checkpointStatus, 'ACTIVE');
      final cp = await LocalDb.instance.getCheckpointById('cp-001');
      expect(cp!.status, 'ACTIVE');
      provider.dispose();
    });
  });
}
