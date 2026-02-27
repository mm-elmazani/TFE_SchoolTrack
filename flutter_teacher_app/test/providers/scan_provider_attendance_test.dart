/// Tests unitaires pour ScanProvider — US 2.3.
///
/// Vérifie : startSession() (chargement élèves + présences préexistantes),
/// getters presentStudents / missingStudents, scanInfoOf(),
/// mise à jour temps réel après chaque scan.
///
/// NFC non testé (dépend du hardware). startSession() est appelé via
/// un helper qui absorbe l'éventuelle PlatformException NFC ; les données
/// (students + presentMap) sont chargées avant l'init NFC.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_teacher_app/core/database/local_db.dart';
import 'package:flutter_teacher_app/features/scan/models/attendance_record.dart';
import 'package:flutter_teacher_app/features/scan/providers/scan_provider.dart';
import 'package:flutter_teacher_app/features/trips/models/offline_bundle.dart';

// ----------------------------------------------------------------
// Fixtures — 3 élèves pour les tests de tri et de filtrage
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
        OfflineStudent(
          id: 'student-003',
          firstName: 'Alice',
          lastName: 'Bernard',
          assignment: OfflineAssignment(
            tokenUid: 'CC:CC:CC:CC',
            assignmentType: 'QR_PHYSICAL',
          ),
        ),
      ],
      checkpoints: const [],
      generatedAt: DateTime(2026, 6, 15),
    );

ScanProvider _makeProvider() =>
    ScanProvider(tripId: 'trip-001', checkpointId: 'cp-001');

/// Lance startSession() en ignorant les erreurs NFC (pas de hardware en tests).
/// Les données (students + presentMap) sont chargées aux étapes 1-4
/// de startSession(), avant l'init NFC qui arrive en dernier.
Future<void> _startSession(
  ScanProvider provider,
  List<OfflineStudent> students,
) async {
  try {
    await provider.startSession(students);
  } catch (_) {
    // PlatformException NFC en environnement de test — ignoré.
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
  // startSession() — chargement de la liste d'élèves
  // ----------------------------------------------------------------

  group('ScanProvider.startSession — liste des élèves', () {
    test('totalStudents est mis à jour', () async {
      await LocalDb.instance.saveBundle(_makeBundle());
      final students = await LocalDb.instance.getStudents('trip-001');
      final provider = _makeProvider();

      await _startSession(provider, students);

      expect(provider.totalStudents, 3);
      provider.dispose();
    });

    test('presentStudents vide si aucune présence préexistante', () async {
      await LocalDb.instance.saveBundle(_makeBundle());
      final students = await LocalDb.instance.getStudents('trip-001');
      final provider = _makeProvider();

      await _startSession(provider, students);

      expect(provider.presentStudents, isEmpty);
      provider.dispose();
    });

    test('missingStudents contient tous les élèves au démarrage', () async {
      await LocalDb.instance.saveBundle(_makeBundle());
      final students = await LocalDb.instance.getStudents('trip-001');
      final provider = _makeProvider();

      await _startSession(provider, students);

      expect(provider.missingStudents.length, 3);
      provider.dispose();
    });

    test('missingStudents suit l\'ordre alphabétique de getStudents()', () async {
      await LocalDb.instance.saveBundle(_makeBundle());
      // getStudents() retourne les élèves triés last_name ASC
      // Bernard < Dupont < Martin
      final students = await LocalDb.instance.getStudents('trip-001');
      final provider = _makeProvider();

      await _startSession(provider, students);

      final missing = provider.missingStudents;
      expect(missing[0].lastName, 'Bernard');
      expect(missing[1].lastName, 'Dupont');
      expect(missing[2].lastName, 'Martin');
      provider.dispose();
    });
  });

  // ----------------------------------------------------------------
  // startSession() — chargement des présences préexistantes (reprise)
  // ----------------------------------------------------------------

  group('ScanProvider.startSession — présences préexistantes', () {
    test('presentCount initialisé depuis SQLite', () async {
      await LocalDb.instance.saveBundle(_makeBundle());
      await LocalDb.instance.saveAttendance(AttendanceRecord(
        id: 'att-001',
        tripId: 'trip-001',
        checkpointId: 'cp-001',
        studentId: 'student-001',
        scannedAt: DateTime(2026, 6, 15, 9, 0),
        scanMethod: ScanMethod.qrPhysical,
        scanSequence: 1,
        isManual: false,
      ));

      final students = await LocalDb.instance.getStudents('trip-001');
      final provider = _makeProvider();

      await _startSession(provider, students);

      expect(provider.presentCount, 1);
      provider.dispose();
    });

    test('presentStudents contient l\'élève préexistant', () async {
      await LocalDb.instance.saveBundle(_makeBundle());
      await LocalDb.instance.saveAttendance(AttendanceRecord(
        id: 'att-001',
        tripId: 'trip-001',
        checkpointId: 'cp-001',
        studentId: 'student-002',
        scannedAt: DateTime(2026, 6, 15, 9, 0),
        scanMethod: ScanMethod.nfcPhysical,
        scanSequence: 1,
        isManual: false,
      ));

      final students = await LocalDb.instance.getStudents('trip-001');
      final provider = _makeProvider();

      await _startSession(provider, students);

      expect(provider.presentStudents.length, 1);
      expect(provider.presentStudents.first.id, 'student-002');
      provider.dispose();
    });

    test('missingStudents exclut les élèves déjà scannés', () async {
      await LocalDb.instance.saveBundle(_makeBundle());
      await LocalDb.instance.saveAttendance(AttendanceRecord(
        id: 'att-001',
        tripId: 'trip-001',
        checkpointId: 'cp-001',
        studentId: 'student-001',
        scannedAt: DateTime(2026, 6, 15, 9, 0),
        scanMethod: ScanMethod.qrPhysical,
        scanSequence: 1,
        isManual: false,
      ));

      final students = await LocalDb.instance.getStudents('trip-001');
      final provider = _makeProvider();

      await _startSession(provider, students);

      expect(provider.missingStudents.length, 2);
      expect(
        provider.missingStudents.any((s) => s.id == 'student-001'),
        isFalse,
      );
      provider.dispose();
    });

    test('scanInfoOf() retourne les données du scan préexistant', () async {
      await LocalDb.instance.saveBundle(_makeBundle());
      await LocalDb.instance.saveAttendance(AttendanceRecord(
        id: 'att-001',
        tripId: 'trip-001',
        checkpointId: 'cp-001',
        studentId: 'student-001',
        scannedAt: DateTime(2026, 6, 15, 9, 30),
        scanMethod: ScanMethod.nfcPhysical,
        scanSequence: 1,
        isManual: false,
      ));

      final students = await LocalDb.instance.getStudents('trip-001');
      final provider = _makeProvider();

      await _startSession(provider, students);

      final info = provider.scanInfoOf('student-001');
      expect(info, isNotNull);
      expect(info!.scanMethod, ScanMethod.nfcPhysical);
      provider.dispose();
    });

    test('attendances d\'un autre checkpoint ne sont pas chargées', () async {
      await LocalDb.instance.saveBundle(_makeBundle());
      // Présence pour un checkpoint différent
      await LocalDb.instance.saveAttendance(AttendanceRecord(
        id: 'att-autre',
        tripId: 'trip-001',
        checkpointId: 'cp-autre',
        studentId: 'student-001',
        scannedAt: DateTime(2026, 6, 15, 8, 0),
        scanMethod: ScanMethod.qrPhysical,
        scanSequence: 1,
        isManual: false,
      ));

      final students = await LocalDb.instance.getStudents('trip-001');
      final provider = _makeProvider(); // checkpointId: 'cp-001'

      await _startSession(provider, students);

      expect(provider.presentCount, 0);
      expect(provider.missingStudents.length, 3);
      provider.dispose();
    });
  });

  // ----------------------------------------------------------------
  // Mise à jour en temps réel après chaque scan
  // ----------------------------------------------------------------

  group('ScanProvider — mise à jour temps réel', () {
    test('élève présent dans presentStudents après scan réussi', () async {
      await LocalDb.instance.saveBundle(_makeBundle());
      final students = await LocalDb.instance.getStudents('trip-001');
      final provider = _makeProvider();
      await _startSession(provider, students);

      await provider.onQrDetected('AA:BB:CC:DD');

      expect(
        provider.presentStudents.any((s) => s.id == 'student-001'),
        isTrue,
      );
      provider.dispose();
    });

    test('élève absent de missingStudents après scan réussi', () async {
      await LocalDb.instance.saveBundle(_makeBundle());
      final students = await LocalDb.instance.getStudents('trip-001');
      final provider = _makeProvider();
      await _startSession(provider, students);

      await provider.onQrDetected('AA:BB:CC:DD');

      expect(
        provider.missingStudents.any((s) => s.id == 'student-001'),
        isFalse,
      );
      provider.dispose();
    });

    test('missingStudents vide quand tous les élèves sont scannés', () async {
      await LocalDb.instance.saveBundle(_makeBundle());
      final students = await LocalDb.instance.getStudents('trip-001');
      final provider = _makeProvider();
      await _startSession(provider, students);

      await provider.onQrDetected('AA:BB:CC:DD');
      provider.resumeScanning();
      await provider.onQrDetected('BB:BB:BB:BB');
      provider.resumeScanning();
      await provider.onQrDetected('CC:CC:CC:CC');

      expect(provider.missingStudents, isEmpty);
      expect(provider.presentStudents.length, 3);
      provider.dispose();
    });

    test('doublon ne modifie pas la taille de presentStudents', () async {
      await LocalDb.instance.saveBundle(_makeBundle());
      final students = await LocalDb.instance.getStudents('trip-001');
      final provider = _makeProvider();
      await _startSession(provider, students);

      await provider.onQrDetected('AA:BB:CC:DD'); // premier scan
      provider.resumeScanning();
      await provider.onQrDetected('AA:BB:CC:DD'); // doublon

      expect(provider.presentStudents.length, 1);
      expect(provider.missingStudents.length, 2);
      provider.dispose();
    });
  });

  // ----------------------------------------------------------------
  // scanInfoOf()
  // ----------------------------------------------------------------

  group('ScanProvider.scanInfoOf', () {
    test('retourne null pour un élève non encore scanné', () async {
      await LocalDb.instance.saveBundle(_makeBundle());
      final students = await LocalDb.instance.getStudents('trip-001');
      final provider = _makeProvider();
      await _startSession(provider, students);

      expect(provider.scanInfoOf('student-001'), isNull);
      provider.dispose();
    });

    test('retourne StudentScanInfo avec la bonne méthode', () async {
      await LocalDb.instance.saveBundle(_makeBundle());
      final students = await LocalDb.instance.getStudents('trip-001');
      final provider = _makeProvider();
      await _startSession(provider, students);

      await provider.onQrDetected('QRD-AA:BB:CC:DD'); // QR_DIGITAL

      final info = provider.scanInfoOf('student-001');
      expect(info, isNotNull);
      expect(info!.scanMethod, ScanMethod.qrDigital);
      provider.dispose();
    });

    test('scannedAt est dans la fenêtre temporelle du scan', () async {
      await LocalDb.instance.saveBundle(_makeBundle());
      final students = await LocalDb.instance.getStudents('trip-001');
      final provider = _makeProvider();
      await _startSession(provider, students);

      final before = DateTime.now();
      await provider.onQrDetected('AA:BB:CC:DD');
      final after = DateTime.now();

      final scannedAt = provider.scanInfoOf('student-001')!.scannedAt;
      expect(scannedAt.isAfter(before.subtract(const Duration(seconds: 1))), isTrue);
      expect(scannedAt.isBefore(after.add(const Duration(seconds: 1))), isTrue);
      provider.dispose();
    });

    test('doublon conserve la méthode du premier scan', () async {
      await LocalDb.instance.saveBundle(_makeBundle());
      final students = await LocalDb.instance.getStudents('trip-001');
      final provider = _makeProvider();
      await _startSession(provider, students);

      // Premier scan : QR digital
      await provider.onQrDetected('QRD-AA:BB:CC:DD');
      provider.resumeScanning();
      // Doublon avec méthode différente (QR physique sans préfixe)
      await provider.onQrDetected('AA:BB:CC:DD');

      // La méthode du premier scan est conservée (no update on duplicate)
      expect(provider.scanInfoOf('student-001')!.scanMethod, ScanMethod.qrDigital);
      provider.dispose();
    });
  });

  // ----------------------------------------------------------------
  // presentStudents — tri par scannedAt DESC
  // ----------------------------------------------------------------

  group('ScanProvider.presentStudents — tri par scannedAt DESC', () {
    test('dernier élève scanné apparaît en tête de liste', () async {
      await LocalDb.instance.saveBundle(_makeBundle());
      final students = await LocalDb.instance.getStudents('trip-001');
      final provider = _makeProvider();
      await _startSession(provider, students);

      // student-001 scanné en premier
      await provider.onQrDetected('AA:BB:CC:DD');
      provider.resumeScanning();
      // Délai pour garantir un scannedAt différent
      await Future.delayed(const Duration(milliseconds: 10));
      // student-002 scanné en second (plus récent)
      await provider.onQrDetected('BB:BB:BB:BB');

      final present = provider.presentStudents;
      expect(present.length, 2);
      // student-002 (Martin) en premier car plus récent
      expect(present.first.id, 'student-002');
      expect(present.last.id, 'student-001');
      provider.dispose();
    });

    test('ordre inversé si student-002 scanné avant student-001', () async {
      await LocalDb.instance.saveBundle(_makeBundle());
      final students = await LocalDb.instance.getStudents('trip-001');
      final provider = _makeProvider();
      await _startSession(provider, students);

      // student-002 scanné en premier
      await provider.onQrDetected('BB:BB:BB:BB');
      provider.resumeScanning();
      await Future.delayed(const Duration(milliseconds: 10));
      // student-001 scanné en second (plus récent)
      await provider.onQrDetected('AA:BB:CC:DD');

      final present = provider.presentStudents;
      expect(present.first.id, 'student-001'); // plus récent
      expect(present.last.id, 'student-002');
      provider.dispose();
    });
  });
}
