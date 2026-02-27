/// Tests unitaires pour LocalDb (US 2.1).
/// Utilise sqflite_common_ffi avec base en mémoire pour isoler chaque test.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_teacher_app/core/database/local_db.dart';
import 'package:flutter_teacher_app/features/trips/models/offline_bundle.dart';

// ----------------------------------------------------------------
// Fixtures
// ----------------------------------------------------------------

OfflineDataBundle _makeBundle({
  String tripId = 'trip-001',
  List<OfflineStudent>? students,
  List<OfflineCheckpoint>? checkpoints,
}) {
  return OfflineDataBundle(
    trip: OfflineTripInfo(
      id: tripId,
      destination: 'Paris',
      date: '2026-06-15',
      description: 'Sortie culturelle',
      status: 'PLANNED',
    ),
    students: students ??
        [
          const OfflineStudent(
            id: 'student-001',
            firstName: 'Jean',
            lastName: 'Dupont',
            assignment: OfflineAssignment(
              tokenUid: 'AA:BB:CC:DD',
              assignmentType: 'NFC_PHYSICAL',
            ),
          ),
          const OfflineStudent(
            id: 'student-002',
            firstName: 'Marie',
            lastName: 'Martin',
          ),
        ],
    checkpoints: checkpoints ??
        [
          const OfflineCheckpoint(
            id: 'cp-001',
            name: 'Entrée',
            sequenceOrder: 1,
            status: 'DRAFT',
          ),
          const OfflineCheckpoint(
            id: 'cp-002',
            name: 'Sortie',
            sequenceOrder: 2,
            status: 'DRAFT',
          ),
        ],
    generatedAt: DateTime(2026, 6, 15, 8, 0, 0),
  );
}

// ----------------------------------------------------------------
// Setup
// ----------------------------------------------------------------

void main() {
  setUpAll(() {
    // Initialiser SQLite FFI (fonctionne sur Windows/Linux/macOS en test)
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
    // Chaque test utilise une BDD en mémoire isolée
    LocalDb.testDatabasePath = inMemoryDatabasePath;
  });

  tearDown(() async {
    await LocalDb.instance.closeForTest();
  });

  // ----------------------------------------------------------------
  // saveBundle
  // ----------------------------------------------------------------

  group('LocalDb.saveBundle', () {
    test('sauvegarde le voyage dans la table trips', () async {
      await LocalDb.instance.saveBundle(_makeBundle());

      final dt = await LocalDb.instance.getTripDownloadedAt('trip-001');
      expect(dt, isNotNull);
    });

    test('sauvegarde les élèves avec et sans assignation', () async {
      await LocalDb.instance.saveBundle(_makeBundle());

      final students = await LocalDb.instance.getStudents('trip-001');
      expect(students.length, 2);

      final dupont = students.firstWhere((s) => s.id == 'student-001');
      expect(dupont.assignment!.tokenUid, 'AA:BB:CC:DD');
      expect(dupont.assignment!.assignmentType, 'NFC_PHYSICAL');

      final martin = students.firstWhere((s) => s.id == 'student-002');
      expect(martin.assignment, isNull);
    });

    test('sauvegarde les checkpoints dans le bon ordre', () async {
      await LocalDb.instance.saveBundle(_makeBundle());

      final cps = await LocalDb.instance.getCheckpoints('trip-001');
      expect(cps.length, 2);
      expect(cps[0].name, 'Entrée');
      expect(cps[0].sequenceOrder, 1);
      expect(cps[1].name, 'Sortie');
      expect(cps[1].sequenceOrder, 2);
    });

    test('re-téléchargement écrase proprement les données existantes', () async {
      await LocalDb.instance.saveBundle(_makeBundle());

      // Re-téléchargement avec un seul élève
      final updatedBundle = _makeBundle(
        students: [
          const OfflineStudent(
            id: 'student-003',
            firstName: 'Paul',
            lastName: 'Durand',
          ),
        ],
        checkpoints: [],
      );
      await LocalDb.instance.saveBundle(updatedBundle);

      final students = await LocalDb.instance.getStudents('trip-001');
      expect(students.length, 1);
      expect(students[0].id, 'student-003');

      final cps = await LocalDb.instance.getCheckpoints('trip-001');
      expect(cps, isEmpty);
    });
  });

  // ----------------------------------------------------------------
  // isTripReady
  // ----------------------------------------------------------------

  group('LocalDb.isTripReady', () {
    test('retourne true pour un voyage fraîchement téléchargé', () async {
      await LocalDb.instance.saveBundle(_makeBundle());

      final ready = await LocalDb.instance.isTripReady('trip-001');
      expect(ready, isTrue);
    });

    test('retourne false pour un voyage non téléchargé', () async {
      final ready = await LocalDb.instance.isTripReady('trip-inexistant');
      expect(ready, isFalse);
    });

    test('retourne false si le cache est expiré (> 7 jours)', () async {
      // Insérer manuellement un voyage avec un timestamp expiré
      final db = await LocalDb.instance.database;
      final expiredTs =
          DateTime.now().millisecondsSinceEpoch - (8 * 24 * 60 * 60 * 1000);
      await db.insert('trips', {
        'id': 'trip-old',
        'destination': 'Ancien voyage',
        'date': '2026-01-01',
        'description': null,
        'status': 'PLANNED',
        'downloaded_at': expiredTs,
      });

      final ready = await LocalDb.instance.isTripReady('trip-old');
      expect(ready, isFalse);
    });
  });

  // ----------------------------------------------------------------
  // getStudents
  // ----------------------------------------------------------------

  group('LocalDb.getStudents', () {
    test('retourne les élèves triés par nom puis prénom', () async {
      final bundle = _makeBundle(
        students: [
          const OfflineStudent(
            id: 's3',
            firstName: 'Alice',
            lastName: 'Zola',
          ),
          const OfflineStudent(
            id: 's1',
            firstName: 'Jean',
            lastName: 'Dupont',
          ),
          const OfflineStudent(
            id: 's2',
            firstName: 'Marie',
            lastName: 'Dupont',
          ),
        ],
        checkpoints: [],
      );
      await LocalDb.instance.saveBundle(bundle);

      final students = await LocalDb.instance.getStudents('trip-001');
      expect(students[0].lastName, 'Dupont');
      expect(students[0].firstName, 'Jean');
      expect(students[1].lastName, 'Dupont');
      expect(students[1].firstName, 'Marie');
      expect(students[2].lastName, 'Zola');
    });

    test('retourne liste vide si aucun élève pour ce voyage', () async {
      final students = await LocalDb.instance.getStudents('trip-vide');
      expect(students, isEmpty);
    });
  });

  // ----------------------------------------------------------------
  // getCheckpoints
  // ----------------------------------------------------------------

  group('LocalDb.getCheckpoints', () {
    test('retourne les checkpoints triés par sequence_order', () async {
      final bundle = _makeBundle(
        checkpoints: [
          const OfflineCheckpoint(
            id: 'cp-b',
            name: 'Étape 2',
            sequenceOrder: 2,
            status: 'DRAFT',
          ),
          const OfflineCheckpoint(
            id: 'cp-a',
            name: 'Étape 1',
            sequenceOrder: 1,
            status: 'ACTIVE',
          ),
        ],
      );
      await LocalDb.instance.saveBundle(bundle);

      final cps = await LocalDb.instance.getCheckpoints('trip-001');
      expect(cps[0].name, 'Étape 1');
      expect(cps[1].name, 'Étape 2');
    });

    test('retourne liste vide si aucun checkpoint', () async {
      final cps = await LocalDb.instance.getCheckpoints('trip-vide');
      expect(cps, isEmpty);
    });
  });
}
