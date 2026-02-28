/// Tests unitaires pour ScanProvider.markManually() — US 2.4.
///
/// Vérifie : présence enregistrée en SQLite, mise à jour des listes
/// temps réel (presentStudents / missingStudents), compteur presentCount,
/// scanMethod = 'MANUAL', justification et commentaire persistés,
/// idempotence sur doublon manuel.
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

OfflineDataBundle _makeBundle() => OfflineDataBundle(
      trip: const OfflineTripInfo(
        id: 'trip-001',
        destination: 'Bruges',
        date: '2026-05-20',
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
        OfflineStudent(
          id: 'student-002',
          firstName: 'Marie',
          lastName: 'Martin',
          assignment: OfflineAssignment(
            tokenUid: 'BB:BB:BB:BB',
            assignmentType: 'QR_PHYSICAL',
          ),
        ),
        OfflineStudent(
          id: 'student-003',
          firstName: 'Alice',
          lastName: 'Bernard',
        ),
      ],
      checkpoints: const [],
      generatedAt: DateTime(2026, 5, 20),
    );

const _student1 = OfflineStudent(
  id: 'student-001',
  firstName: 'Jean',
  lastName: 'Dupont',
  assignment: OfflineAssignment(
    tokenUid: 'AA:BB:CC:DD',
    assignmentType: 'NFC_PHYSICAL',
  ),
);

const _student2 = OfflineStudent(
  id: 'student-002',
  firstName: 'Marie',
  lastName: 'Martin',
  assignment: OfflineAssignment(
    tokenUid: 'BB:BB:BB:BB',
    assignmentType: 'QR_PHYSICAL',
  ),
);

ScanProvider _makeProvider() =>
    ScanProvider(tripId: 'trip-001', checkpointId: 'cp-001');

/// Démarre la session en ignorant les erreurs NFC (pas de hardware en tests).
Future<void> _startSession(
  ScanProvider provider,
  List<OfflineStudent> students,
) async {
  try {
    await provider.startSession(students);
  } catch (_) {
    // PlatformException NFC ignorée en environnement de test.
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
  // markManually() — mise à jour des listes temps réel
  // ----------------------------------------------------------------

  group('ScanProvider.markManually — listes temps réel', () {
    test('élève passe de missingStudents à presentStudents', () async {
      await LocalDb.instance.saveBundle(_makeBundle());
      final students = await LocalDb.instance.getStudents('trip-001');
      final provider = _makeProvider();
      await _startSession(provider, students);

      await provider.markManually(
        student: _student1,
        justification: 'BADGE_MISSING',
      );

      expect(
        provider.presentStudents.any((s) => s.id == 'student-001'),
        isTrue,
      );
      expect(
        provider.missingStudents.any((s) => s.id == 'student-001'),
        isFalse,
      );
      provider.dispose();
    });

    test('presentCount augmente de 1 après markManually', () async {
      await LocalDb.instance.saveBundle(_makeBundle());
      final students = await LocalDb.instance.getStudents('trip-001');
      final provider = _makeProvider();
      await _startSession(provider, students);

      expect(provider.presentCount, 0);
      await provider.markManually(
        student: _student1,
        justification: 'SCANNER_FAILURE',
      );
      expect(provider.presentCount, 1);
      provider.dispose();
    });

    test('missingCount diminue de 1 après markManually', () async {
      await LocalDb.instance.saveBundle(_makeBundle());
      final students = await LocalDb.instance.getStudents('trip-001');
      final provider = _makeProvider();
      await _startSession(provider, students);

      final missingBefore = provider.missingCount;
      await provider.markManually(
        student: _student2,
        justification: 'TEACHER_CONFIRMATION',
      );
      expect(provider.missingCount, missingBefore - 1);
      provider.dispose();
    });

    test('markManually sur 2 élèves différents : presentCount = 2', () async {
      await LocalDb.instance.saveBundle(_makeBundle());
      final students = await LocalDb.instance.getStudents('trip-001');
      final provider = _makeProvider();
      await _startSession(provider, students);

      await provider.markManually(
        student: _student1,
        justification: 'BADGE_DAMAGED',
      );
      await provider.markManually(
        student: _student2,
        justification: 'BADGE_MISSING',
      );

      expect(provider.presentCount, 2);
      expect(provider.missingStudents.length, 1);
      provider.dispose();
    });
  });

  // ----------------------------------------------------------------
  // markManually() — scanMethod et scanInfoOf()
  // ----------------------------------------------------------------

  group('ScanProvider.markManually — scanMethod MANUAL', () {
    test('scanInfoOf retourne scanMethod MANUAL', () async {
      await LocalDb.instance.saveBundle(_makeBundle());
      final students = await LocalDb.instance.getStudents('trip-001');
      final provider = _makeProvider();
      await _startSession(provider, students);

      await provider.markManually(
        student: _student1,
        justification: 'OTHER',
        comment: 'Problème de bracelet',
      );

      final info = provider.scanInfoOf('student-001');
      expect(info, isNotNull);
      expect(info!.scanMethod, ScanMethod.manual);
      provider.dispose();
    });

    test('scannedAt est récent (< 2s)', () async {
      await LocalDb.instance.saveBundle(_makeBundle());
      final students = await LocalDb.instance.getStudents('trip-001');
      final provider = _makeProvider();
      await _startSession(provider, students);

      final before = DateTime.now();
      await provider.markManually(
        student: _student1,
        justification: 'BADGE_MISSING',
      );
      final after = DateTime.now();

      final scannedAt = provider.scanInfoOf('student-001')!.scannedAt;
      expect(scannedAt.isAfter(before.subtract(const Duration(seconds: 1))), isTrue);
      expect(scannedAt.isBefore(after.add(const Duration(seconds: 1))), isTrue);
      provider.dispose();
    });
  });

  // ----------------------------------------------------------------
  // markManually() — persistance SQLite
  // ----------------------------------------------------------------

  group('ScanProvider.markManually — persistance SQLite', () {
    test('présence enregistrée avec is_manual = true', () async {
      await LocalDb.instance.saveBundle(_makeBundle());
      final students = await LocalDb.instance.getStudents('trip-001');
      final provider = _makeProvider();
      await _startSession(provider, students);

      await provider.markManually(
        student: _student1,
        justification: 'SCANNER_FAILURE',
      );

      final attendances = await LocalDb.instance.getAttendancesByCheckpoint('cp-001');
      expect(attendances.length, 1);
      expect(attendances.first.isManual, isTrue);
      provider.dispose();
    });

    test('scan_method sauvegardé comme MANUAL', () async {
      await LocalDb.instance.saveBundle(_makeBundle());
      final students = await LocalDb.instance.getStudents('trip-001');
      final provider = _makeProvider();
      await _startSession(provider, students);

      await provider.markManually(
        student: _student1,
        justification: 'BADGE_DAMAGED',
      );

      final attendances = await LocalDb.instance.getAttendancesByCheckpoint('cp-001');
      expect(attendances.first.scanMethod, ScanMethod.manual);
      provider.dispose();
    });

    test('justification persistée en SQLite', () async {
      await LocalDb.instance.saveBundle(_makeBundle());
      final students = await LocalDb.instance.getStudents('trip-001');
      final provider = _makeProvider();
      await _startSession(provider, students);

      await provider.markManually(
        student: _student1,
        justification: 'TEACHER_CONFIRMATION',
      );

      final attendances = await LocalDb.instance.getAttendancesByCheckpoint('cp-001');
      expect(attendances.first.justification, 'TEACHER_CONFIRMATION');
      provider.dispose();
    });

    test('commentaire persisté si fourni', () async {
      await LocalDb.instance.saveBundle(_makeBundle());
      final students = await LocalDb.instance.getStudents('trip-001');
      final provider = _makeProvider();
      await _startSession(provider, students);

      await provider.markManually(
        student: _student1,
        justification: 'OTHER',
        comment: 'Bracelet oublié à la maison',
      );

      final attendances = await LocalDb.instance.getAttendancesByCheckpoint('cp-001');
      expect(attendances.first.comment, 'Bracelet oublié à la maison');
      provider.dispose();
    });

    test('commentaire null si non fourni', () async {
      await LocalDb.instance.saveBundle(_makeBundle());
      final students = await LocalDb.instance.getStudents('trip-001');
      final provider = _makeProvider();
      await _startSession(provider, students);

      await provider.markManually(
        student: _student1,
        justification: 'BADGE_MISSING',
      );

      final attendances = await LocalDb.instance.getAttendancesByCheckpoint('cp-001');
      expect(attendances.first.comment, isNull);
      provider.dispose();
    });

    test('enregistrement non synchronisé (synced_at IS NULL)', () async {
      await LocalDb.instance.saveBundle(_makeBundle());
      final students = await LocalDb.instance.getStudents('trip-001');
      final provider = _makeProvider();
      await _startSession(provider, students);

      await provider.markManually(
        student: _student1,
        justification: 'SCANNER_FAILURE',
      );

      final attendances = await LocalDb.instance.getAttendancesByCheckpoint('cp-001');
      expect(attendances.first.isSynced, isFalse);
      provider.dispose();
    });
  });

  // ----------------------------------------------------------------
  // markManually() — idempotence sur doublon
  // ----------------------------------------------------------------

  group('ScanProvider.markManually — doublon', () {
    test('double appel ne double pas presentCount', () async {
      await LocalDb.instance.saveBundle(_makeBundle());
      final students = await LocalDb.instance.getStudents('trip-001');
      final provider = _makeProvider();
      await _startSession(provider, students);

      await provider.markManually(
        student: _student1,
        justification: 'BADGE_MISSING',
      );
      await provider.markManually(
        student: _student1,
        justification: 'OTHER',
        comment: 'Double appel',
      );

      // Le compteur ne doit pas dépasser 1 pour cet élève
      expect(provider.presentCount, 1);
      provider.dispose();
    });

    test('double appel conserve la méthode du premier marquage', () async {
      await LocalDb.instance.saveBundle(_makeBundle());
      final students = await LocalDb.instance.getStudents('trip-001');
      final provider = _makeProvider();
      await _startSession(provider, students);

      await provider.markManually(
        student: _student1,
        justification: 'BADGE_MISSING',
      );
      await provider.markManually(
        student: _student1,
        justification: 'OTHER',
      );

      // La map conserve le premier StudentScanInfo (putIfAbsent implicite)
      expect(provider.scanInfoOf('student-001')!.scanMethod, ScanMethod.manual);
      provider.dispose();
    });

    test('double appel crée 2 enregistrements SQLite (historique)', () async {
      await LocalDb.instance.saveBundle(_makeBundle());
      final students = await LocalDb.instance.getStudents('trip-001');
      final provider = _makeProvider();
      await _startSession(provider, students);

      await provider.markManually(
        student: _student1,
        justification: 'BADGE_MISSING',
      );
      await provider.markManually(
        student: _student1,
        justification: 'OTHER',
        comment: 'Confirmation enseignant',
      );

      // Deux lignes SQL avec scan_sequence 1 et 2
      final attendances = await LocalDb.instance.getAttendancesByCheckpoint('cp-001');
      expect(attendances.length, 2);
      provider.dispose();
    });
  });

  // ----------------------------------------------------------------
  // markManually() + scan hybride — cohabitation
  // ----------------------------------------------------------------

  group('ScanProvider.markManually — cohabitation avec scan QR/NFC', () {
    test('marquer manuellement après un scan QR ne change pas le compteur', () async {
      await LocalDb.instance.saveBundle(_makeBundle());
      final students = await LocalDb.instance.getStudents('trip-001');
      final provider = _makeProvider();
      await _startSession(provider, students);

      // Scan QR de student-001
      await provider.onQrDetected('AA:BB:CC:DD');
      provider.resumeScanning();
      expect(provider.presentCount, 1);

      // Marquage manuel du même élève → compteur ne doit pas changer
      await provider.markManually(
        student: _student1,
        justification: 'OTHER',
      );
      expect(provider.presentCount, 1);
      provider.dispose();
    });

    test('présences manuelles et QR sont toutes dans SQLite', () async {
      await LocalDb.instance.saveBundle(_makeBundle());
      final students = await LocalDb.instance.getStudents('trip-001');
      final provider = _makeProvider();
      await _startSession(provider, students);

      await provider.onQrDetected('AA:BB:CC:DD'); // student-001 par QR
      provider.resumeScanning();
      await provider.markManually(               // student-002 manuellement
        student: _student2,
        justification: 'BADGE_MISSING',
      );

      final attendances = await LocalDb.instance.getAttendancesByCheckpoint('cp-001');
      expect(attendances.length, 2);
      expect(attendances.any((a) => a.scanMethod == ScanMethod.qrPhysical), isTrue);
      expect(attendances.any((a) => a.scanMethod == ScanMethod.manual), isTrue);
      provider.dispose();
    });
  });

  // ----------------------------------------------------------------
  // justificationOptions — constante
  // ----------------------------------------------------------------

  group('ScanProvider.justificationOptions', () {
    test('contient au moins 3 options', () {
      expect(ScanProvider.justificationOptions.length, greaterThanOrEqualTo(3));
    });

    test('chaque option a un code et un libellé non vides', () {
      for (final (code, label) in ScanProvider.justificationOptions) {
        expect(code, isNotEmpty);
        expect(label, isNotEmpty);
      }
    });
  });
}
