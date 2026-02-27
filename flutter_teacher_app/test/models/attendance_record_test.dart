/// Tests unitaires pour AttendanceRecord (US 2.2).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_teacher_app/features/scan/models/attendance_record.dart';

void main() {
  group('ScanMethod', () {
    test('valeurs des constantes', () {
      expect(ScanMethod.nfcPhysical, 'NFC_PHYSICAL');
      expect(ScanMethod.qrPhysical, 'QR_PHYSICAL');
      expect(ScanMethod.qrDigital, 'QR_DIGITAL');
      expect(ScanMethod.manual, 'MANUAL');
    });
  });

  group('AttendanceRecord', () {
    AttendanceRecord make({
      int scanSequence = 1,
      DateTime? syncedAt,
      bool isManual = false,
    }) =>
        AttendanceRecord(
          id: 'uuid-1',
          tripId: 'trip-001',
          checkpointId: 'cp-001',
          studentId: 'student-001',
          scannedAt: DateTime(2026, 6, 15, 10, 0),
          scanMethod: ScanMethod.nfcPhysical,
          scanSequence: scanSequence,
          isManual: isManual,
          syncedAt: syncedAt,
        );

    test('isSynced retourne false si syncedAt est null', () {
      expect(make().isSynced, isFalse);
    });

    test('isSynced retourne true si syncedAt est défini', () {
      expect(make(syncedAt: DateTime(2026, 6, 15, 11, 0)).isSynced, isTrue);
    });

    test('isDuplicate retourne false si scanSequence = 1', () {
      expect(make(scanSequence: 1).isDuplicate, isFalse);
    });

    test('isDuplicate retourne true si scanSequence > 1', () {
      expect(make(scanSequence: 2).isDuplicate, isTrue);
      expect(make(scanSequence: 3).isDuplicate, isTrue);
    });

    test('scanSequence par défaut est 1', () {
      expect(make().scanSequence, 1);
    });

    test('isManual par défaut est false', () {
      expect(make().isManual, isFalse);
    });

    test('champs optionnels sont null par défaut', () {
      final r = make();
      expect(r.justification, isNull);
      expect(r.comment, isNull);
      expect(r.syncedAt, isNull);
    });
  });
}
