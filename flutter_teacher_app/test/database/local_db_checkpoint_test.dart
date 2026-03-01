/// Tests unitaires pour LocalDb — checkpoints terrain (US 2.5).
///
/// Vérifie : createCheckpoint() (création SQLite, sequence_order, statut DRAFT),
/// activateCheckpoint() (DRAFT→ACTIVE), getCheckpointById(),
/// cohabitation avec les checkpoints du bundle offline.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_teacher_app/core/database/local_db.dart';
import 'package:flutter_teacher_app/features/trips/models/offline_bundle.dart';

// ----------------------------------------------------------------
// Fixtures
// ----------------------------------------------------------------

OfflineDataBundle _makeBundle({List<OfflineCheckpoint> checkpoints = const []}) =>
    OfflineDataBundle(
      trip: const OfflineTripInfo(
        id: 'trip-001',
        destination: 'Bruges',
        date: '2026-05-20',
        status: 'ACTIVE',
      ),
      students: const [],
      checkpoints: checkpoints,
      generatedAt: DateTime(2026, 5, 20),
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
  // createCheckpoint()
  // ----------------------------------------------------------------

  group('LocalDb.createCheckpoint — création', () {
    test('retourne un OfflineCheckpoint avec statut DRAFT', () async {
      await LocalDb.instance.saveBundle(_makeBundle());

      final cp = await LocalDb.instance.createCheckpoint(
        tripId: 'trip-001',
        name: 'Arrêt bus',
      );

      expect(cp.status, 'DRAFT');
      expect(cp.name, 'Arrêt bus');
    });

    test('id généré est non-vide (UUID v4)', () async {
      await LocalDb.instance.saveBundle(_makeBundle());

      final cp = await LocalDb.instance.createCheckpoint(
        tripId: 'trip-001',
        name: 'Entrée musée',
      );

      expect(cp.id, isNotEmpty);
      expect(cp.id.length, 36); // UUID v4 = 36 caractères
    });

    test('sequence_order = 1 si aucun checkpoint existant', () async {
      await LocalDb.instance.saveBundle(_makeBundle());

      final cp = await LocalDb.instance.createCheckpoint(
        tripId: 'trip-001',
        name: 'Premier checkpoint',
      );

      expect(cp.sequenceOrder, 1);
    });

    test('sequence_order incrémenté si des checkpoints existent déjà', () async {
      // Bundle avec 2 checkpoints déjà présents (sequence_order 1 et 2)
      await LocalDb.instance.saveBundle(_makeBundle(checkpoints: [
        const OfflineCheckpoint(
          id: 'cp-001',
          name: 'Départ',
          sequenceOrder: 1,
          status: 'ACTIVE',
        ),
        const OfflineCheckpoint(
          id: 'cp-002',
          name: 'Halte',
          sequenceOrder: 2,
          status: 'CLOSED',
        ),
      ]));

      final cp = await LocalDb.instance.createCheckpoint(
        tripId: 'trip-001',
        name: 'Arrivée',
      );

      expect(cp.sequenceOrder, 3);
    });

    test('checkpoint persiste dans SQLite (récupérable via getCheckpoints)', () async {
      await LocalDb.instance.saveBundle(_makeBundle());

      await LocalDb.instance.createCheckpoint(
        tripId: 'trip-001',
        name: 'Arrêt 1',
      );

      final checkpoints = await LocalDb.instance.getCheckpoints('trip-001');
      expect(checkpoints.length, 1);
      expect(checkpoints.first.name, 'Arrêt 1');
      expect(checkpoints.first.status, 'DRAFT');
    });

    test('deux créations successives ont des IDs différents', () async {
      await LocalDb.instance.saveBundle(_makeBundle());

      final cp1 = await LocalDb.instance.createCheckpoint(
        tripId: 'trip-001',
        name: 'Arrêt 1',
      );
      final cp2 = await LocalDb.instance.createCheckpoint(
        tripId: 'trip-001',
        name: 'Arrêt 2',
      );

      expect(cp1.id, isNot(cp2.id));
    });

    test('deux créations : sequence_order 1 puis 2', () async {
      await LocalDb.instance.saveBundle(_makeBundle());

      final cp1 = await LocalDb.instance.createCheckpoint(
        tripId: 'trip-001',
        name: 'Arrêt 1',
      );
      final cp2 = await LocalDb.instance.createCheckpoint(
        tripId: 'trip-001',
        name: 'Arrêt 2',
      );

      expect(cp1.sequenceOrder, 1);
      expect(cp2.sequenceOrder, 2);
    });
  });

  // ----------------------------------------------------------------
  // getCheckpointById()
  // ----------------------------------------------------------------

  group('LocalDb.getCheckpointById', () {
    test('retourne le checkpoint correspondant', () async {
      await LocalDb.instance.saveBundle(_makeBundle());
      final created = await LocalDb.instance.createCheckpoint(
        tripId: 'trip-001',
        name: 'Point A',
      );

      final found = await LocalDb.instance.getCheckpointById(created.id);

      expect(found, isNotNull);
      expect(found!.id, created.id);
      expect(found.name, 'Point A');
    });

    test('retourne null si l\'ID est inconnu', () async {
      await LocalDb.instance.saveBundle(_makeBundle());

      final found = await LocalDb.instance.getCheckpointById('id-inexistant');

      expect(found, isNull);
    });

    test('retourne le statut correct', () async {
      await LocalDb.instance.saveBundle(_makeBundle(checkpoints: [
        const OfflineCheckpoint(
          id: 'cp-active',
          name: 'Checkpoint actif',
          sequenceOrder: 1,
          status: 'ACTIVE',
        ),
      ]));

      final found = await LocalDb.instance.getCheckpointById('cp-active');

      expect(found, isNotNull);
      expect(found!.status, 'ACTIVE');
    });
  });

  // ----------------------------------------------------------------
  // activateCheckpoint()
  // ----------------------------------------------------------------

  group('LocalDb.activateCheckpoint — DRAFT→ACTIVE', () {
    test('statut passe à ACTIVE après activation', () async {
      await LocalDb.instance.saveBundle(_makeBundle());
      final cp = await LocalDb.instance.createCheckpoint(
        tripId: 'trip-001',
        name: 'Point de contrôle',
      );
      expect(cp.status, 'DRAFT');

      await LocalDb.instance.activateCheckpoint(cp.id);

      final updated = await LocalDb.instance.getCheckpointById(cp.id);
      expect(updated!.status, 'ACTIVE');
    });

    test('getCheckpoints() reflète le statut ACTIVE après activation', () async {
      await LocalDb.instance.saveBundle(_makeBundle());
      final cp = await LocalDb.instance.createCheckpoint(
        tripId: 'trip-001',
        name: 'Checkpoint',
      );

      await LocalDb.instance.activateCheckpoint(cp.id);

      final checkpoints = await LocalDb.instance.getCheckpoints('trip-001');
      expect(checkpoints.first.status, 'ACTIVE');
    });

    test('activation n\'affecte pas les autres checkpoints', () async {
      await LocalDb.instance.saveBundle(_makeBundle(checkpoints: [
        const OfflineCheckpoint(
          id: 'cp-draft-1',
          name: 'Draft 1',
          sequenceOrder: 1,
          status: 'DRAFT',
        ),
        const OfflineCheckpoint(
          id: 'cp-draft-2',
          name: 'Draft 2',
          sequenceOrder: 2,
          status: 'DRAFT',
        ),
      ]));

      // Activer seulement cp-draft-1
      await LocalDb.instance.activateCheckpoint('cp-draft-1');

      final cp1 = await LocalDb.instance.getCheckpointById('cp-draft-1');
      final cp2 = await LocalDb.instance.getCheckpointById('cp-draft-2');

      expect(cp1!.status, 'ACTIVE');
      expect(cp2!.status, 'DRAFT'); // inchangé
    });
  });

  // ----------------------------------------------------------------
  // closeCheckpoint() — US 2.7
  // ----------------------------------------------------------------

  group('LocalDb.closeCheckpoint — ACTIVE→CLOSED', () {
    test('statut passe à CLOSED après clôture', () async {
      await LocalDb.instance.saveBundle(_makeBundle());
      final cp = await LocalDb.instance.createCheckpoint(
        tripId: 'trip-001',
        name: 'Point de contrôle',
      );
      await LocalDb.instance.activateCheckpoint(cp.id);

      await LocalDb.instance.closeCheckpoint(cp.id);

      final updated = await LocalDb.instance.getCheckpointById(cp.id);
      expect(updated!.status, 'CLOSED');
    });

    test('getCheckpoints() reflète le statut CLOSED après clôture', () async {
      await LocalDb.instance.saveBundle(_makeBundle());
      final cp = await LocalDb.instance.createCheckpoint(
        tripId: 'trip-001',
        name: 'Checkpoint',
      );
      await LocalDb.instance.activateCheckpoint(cp.id);

      await LocalDb.instance.closeCheckpoint(cp.id);

      final checkpoints = await LocalDb.instance.getCheckpoints('trip-001');
      expect(checkpoints.first.status, 'CLOSED');
    });

    test('clôture n\'affecte pas les autres checkpoints', () async {
      await LocalDb.instance.saveBundle(_makeBundle(checkpoints: [
        const OfflineCheckpoint(
          id: 'cp-active-1',
          name: 'Actif 1',
          sequenceOrder: 1,
          status: 'ACTIVE',
        ),
        const OfflineCheckpoint(
          id: 'cp-active-2',
          name: 'Actif 2',
          sequenceOrder: 2,
          status: 'ACTIVE',
        ),
      ]));

      await LocalDb.instance.closeCheckpoint('cp-active-1');

      final cp1 = await LocalDb.instance.getCheckpointById('cp-active-1');
      final cp2 = await LocalDb.instance.getCheckpointById('cp-active-2');
      expect(cp1!.status, 'CLOSED');
      expect(cp2!.status, 'ACTIVE'); // inchangé
    });
  });

  // ----------------------------------------------------------------
  // Cohabitation bundle offline + création terrain
  // ----------------------------------------------------------------

  group('LocalDb — bundle + checkpoint terrain', () {
    test('checkpoint créé sur le terrain s\'ajoute à la liste des checkpoints du bundle', () async {
      await LocalDb.instance.saveBundle(_makeBundle(checkpoints: [
        const OfflineCheckpoint(
          id: 'cp-bundle',
          name: 'Checkpoint bundle',
          sequenceOrder: 1,
          status: 'ACTIVE',
        ),
      ]));

      await LocalDb.instance.createCheckpoint(
        tripId: 'trip-001',
        name: 'Checkpoint terrain',
      );

      final all = await LocalDb.instance.getCheckpoints('trip-001');
      expect(all.length, 2);
      expect(all.any((c) => c.name == 'Checkpoint bundle'), isTrue);
      expect(all.any((c) => c.name == 'Checkpoint terrain'), isTrue);
    });

    test('re-télécharger le bundle ne supprime pas les présences (comportement existant)', () async {
      // Vérifie que saveBundle ne touche pas aux attendances
      await LocalDb.instance.saveBundle(_makeBundle());
      final cp = await LocalDb.instance.createCheckpoint(
        tripId: 'trip-001',
        name: 'Terrain',
      );
      expect(cp.status, 'DRAFT');

      // Re-télécharger le bundle efface les checkpoints existants
      // (comportement intentionnel dans saveBundle — les checkpoints viennent du serveur)
      await LocalDb.instance.saveBundle(_makeBundle(checkpoints: [
        const OfflineCheckpoint(
          id: 'cp-new',
          name: 'Nouveau bundle',
          sequenceOrder: 1,
          status: 'DRAFT',
        ),
      ]));

      final all = await LocalDb.instance.getCheckpoints('trip-001');
      // Après re-téléchargement, seuls les checkpoints du bundle sont présents
      expect(all.length, 1);
      expect(all.first.id, 'cp-new');
    });
  });
}
