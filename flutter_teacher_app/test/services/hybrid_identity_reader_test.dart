/// Tests unitaires pour HybridIdentityReader.processQrCode (US 2.2).
///
/// Seule la partie QR est testable sans hardware.
/// NFC (startNfc/stopNfc) dépend de NfcManager → testé sur appareil réel.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_teacher_app/core/database/local_db.dart';
import 'package:flutter_teacher_app/core/services/hybrid_identity_reader.dart';
import 'package:flutter_teacher_app/features/scan/models/attendance_record.dart';
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
            tokenUid: 'MARIE-QR-001',
            assignmentType: 'QR_DIGITAL',
          ),
        ),
      ],
      checkpoints: const [],
      generatedAt: DateTime(2026, 6, 15),
    );

HybridIdentityReader _makeReader() => HybridIdentityReader(
      tripId: 'trip-001',
      checkpointId: 'cp-001',
    );

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
  // processQrCode — validation entrée
  // ----------------------------------------------------------------

  group('HybridIdentityReader.processQrCode — entrée invalide', () {
    test('QR vide retourne ScanError', () async {
      final result = await _makeReader().processQrCode('');
      expect(result, isA<ScanError>());
      expect((result as ScanError).message, contains('vide'));
    });

    test('QR uniquement espaces retourne ScanError', () async {
      final result = await _makeReader().processQrCode('   ');
      expect(result, isA<ScanError>());
    });
  });

  // ----------------------------------------------------------------
  // processQrCode — résolution UID inconnue
  // ----------------------------------------------------------------

  group('HybridIdentityReader.processQrCode — UID inconnu', () {
    test('retourne ScanError avec l\'UID brut si UID non assigné', () async {
      await LocalDb.instance.saveBundle(_makeBundle());

      final result = await _makeReader().processQrCode('FF:FF:FF:FF');
      expect(result, isA<ScanError>());
      expect((result as ScanError).uid, 'FF:FF:FF:FF');
    });

    test('retourne ScanError si UID avec préfixe QRD- non reconnu', () async {
      await LocalDb.instance.saveBundle(_makeBundle());

      final result = await _makeReader().processQrCode('QRD-INCONNU');
      expect(result, isA<ScanError>());
      // UID normalisé (sans préfixe) dans le message d'erreur
      expect((result as ScanError).uid, 'INCONNU');
    });
  });

  // ----------------------------------------------------------------
  // processQrCode — détection de la méthode de scan
  // ----------------------------------------------------------------

  group('HybridIdentityReader.processQrCode — méthode de scan', () {
    test('préfixe QRD- → méthode QR_DIGITAL', () async {
      await LocalDb.instance.saveBundle(_makeBundle());

      // QRD-AA:BB:CC:DD → normalise en AA:BB:CC:DD, cherche l'élève
      final result = await _makeReader().processQrCode('QRD-AA:BB:CC:DD');
      expect(result, isA<ScanSuccess>());
      expect((result as ScanSuccess).scanMethod, ScanMethod.qrDigital);
    });

    test('préfixe QRP- → méthode QR_PHYSICAL', () async {
      await LocalDb.instance.saveBundle(_makeBundle());

      final result = await _makeReader().processQrCode('QRP-AA:BB:CC:DD');
      expect(result, isA<ScanSuccess>());
      expect((result as ScanSuccess).scanMethod, ScanMethod.qrPhysical);
    });

    test('sans préfixe → méthode QR_PHYSICAL par défaut', () async {
      await LocalDb.instance.saveBundle(_makeBundle());

      final result = await _makeReader().processQrCode('AA:BB:CC:DD');
      expect(result, isA<ScanSuccess>());
      expect((result as ScanSuccess).scanMethod, ScanMethod.qrPhysical);
    });
  });

  // ----------------------------------------------------------------
  // processQrCode — premier scan
  // ----------------------------------------------------------------

  group('HybridIdentityReader.processQrCode — premier scan', () {
    test('identifie l\'élève correct', () async {
      await LocalDb.instance.saveBundle(_makeBundle());

      final result = await _makeReader().processQrCode('AA:BB:CC:DD');
      expect(result, isA<ScanSuccess>());
      final success = result as ScanSuccess;
      expect(success.student.id, 'student-001');
      expect(success.student.firstName, 'Jean');
    });

    test('isDuplicate = false et scanSequence = 1', () async {
      await LocalDb.instance.saveBundle(_makeBundle());

      final result = await _makeReader().processQrCode('AA:BB:CC:DD');
      final success = result as ScanSuccess;
      expect(success.isDuplicate, isFalse);
      expect(success.scanSequence, 1);
    });

    test('enregistre la présence dans SQLite', () async {
      await LocalDb.instance.saveBundle(_makeBundle());

      await _makeReader().processQrCode('AA:BB:CC:DD');

      final atts =
          await LocalDb.instance.getAttendancesByCheckpoint('cp-001');
      expect(atts.length, 1);
      expect(atts[0].studentId, 'student-001');
      expect(atts[0].scanMethod, ScanMethod.qrPhysical);
    });
  });

  // ----------------------------------------------------------------
  // processQrCode — doublon
  // ----------------------------------------------------------------

  group('HybridIdentityReader.processQrCode — doublon', () {
    test('deuxième scan → isDuplicate = true, scanSequence = 2', () async {
      await LocalDb.instance.saveBundle(_makeBundle());
      final reader = _makeReader();

      await reader.processQrCode('AA:BB:CC:DD'); // premier
      final result = await reader.processQrCode('AA:BB:CC:DD'); // doublon

      expect(result, isA<ScanSuccess>());
      final success = result as ScanSuccess;
      expect(success.isDuplicate, isTrue);
      expect(success.scanSequence, 2);
    });

    test('doublon enregistre quand même une ligne en DB', () async {
      await LocalDb.instance.saveBundle(_makeBundle());
      final reader = _makeReader();

      await reader.processQrCode('AA:BB:CC:DD');
      await reader.processQrCode('AA:BB:CC:DD');

      final atts =
          await LocalDb.instance.getAttendancesByCheckpoint('cp-001');
      expect(atts.length, 2);
    });

    test('scans de deux élèves différents ne se confondent pas', () async {
      await LocalDb.instance.saveBundle(_makeBundle());
      final reader = _makeReader();

      final r1 = await reader.processQrCode('AA:BB:CC:DD');
      final r2 = await reader.processQrCode('MARIE-QR-001');

      expect((r1 as ScanSuccess).isDuplicate, isFalse);
      expect((r2 as ScanSuccess).isDuplicate, isFalse);
      expect(r2.student.id, 'student-002');
    });
  });
}
