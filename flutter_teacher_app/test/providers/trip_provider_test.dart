/// Tests unitaires pour TripProvider (US 2.1).
/// Utilise un FakeApiClient et une LocalDb en mémoire pour isoler la logique.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_teacher_app/core/api/api_client.dart';
import 'package:flutter_teacher_app/core/database/local_db.dart';
import 'package:flutter_teacher_app/features/trips/models/offline_bundle.dart';
import 'package:flutter_teacher_app/features/trips/providers/trip_provider.dart';

// ----------------------------------------------------------------
// Fake ApiClient — évite de vraies requêtes HTTP
// ----------------------------------------------------------------

class FakeApiClient extends ApiClient {
  final List<TripSummary> tripsResult;
  final OfflineDataBundle? bundleResult;
  final ApiException? error;

  FakeApiClient({
    this.tripsResult = const [],
    this.bundleResult,
    this.error,
  }) : super(baseUrl: 'http://fake.local');

  @override
  Future<List<TripSummary>> getTrips() async {
    if (error != null) throw error!;
    return tripsResult;
  }

  @override
  Future<OfflineDataBundle> getOfflineBundle(String tripId) async {
    if (error != null) throw error!;
    return bundleResult!;
  }
}

// ----------------------------------------------------------------
// Fixtures
// ----------------------------------------------------------------

final _trips = [
  const TripSummary(
    id: 'trip-001',
    destination: 'Paris',
    date: '2026-06-15',
    status: 'PLANNED',
    studentCount: 25,
  ),
  const TripSummary(
    id: 'trip-002',
    destination: 'Rome',
    date: '2026-07-01',
    status: 'ACTIVE',
    studentCount: 18,
  ),
];

final _bundle = OfflineDataBundle(
  trip: const OfflineTripInfo(
    id: 'trip-001',
    destination: 'Paris',
    date: '2026-06-15',
    status: 'PLANNED',
  ),
  students: const [
    OfflineStudent(id: 's1', firstName: 'Jean', lastName: 'Dupont'),
  ],
  checkpoints: const [
    OfflineCheckpoint(
      id: 'cp-1',
      name: 'Entrée',
      sequenceOrder: 1,
      status: 'DRAFT',
    ),
  ],
  generatedAt: DateTime(2026, 6, 15),
);

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
  // loadTrips
  // ----------------------------------------------------------------

  group('TripProvider.loadTrips', () {
    test('état initial est idle', () {
      final provider = TripProvider(
        api: FakeApiClient(),
        db: LocalDb.instance,
      );
      expect(provider.listState, TripListState.idle);
      expect(provider.trips, isEmpty);
    });

    test('passe à ready et remplit trips sur succès', () async {
      final provider = TripProvider(
        api: FakeApiClient(tripsResult: _trips),
        db: LocalDb.instance,
      );

      await provider.loadTrips();

      expect(provider.listState, TripListState.ready);
      expect(provider.trips.length, 2);
      expect(provider.trips[0].destination, 'Paris');
      expect(provider.listError, isNull);
    });

    test('passe à error si ApiException', () async {
      final provider = TripProvider(
        api: FakeApiClient(
          error: const ApiException('Serveur inaccessible', statusCode: 503),
        ),
        db: LocalDb.instance,
      );

      await provider.loadTrips();

      expect(provider.listState, TripListState.error);
      expect(provider.listError, contains('Serveur inaccessible'));
      expect(provider.trips, isEmpty);
    });

    test('isReady retourne false pour voyage non téléchargé', () async {
      final provider = TripProvider(
        api: FakeApiClient(tripsResult: _trips),
        db: LocalDb.instance,
      );

      await provider.loadTrips();

      expect(provider.isReady('trip-001'), isFalse);
    });

    test('isReady retourne true après téléchargement', () async {
      final provider = TripProvider(
        api: FakeApiClient(tripsResult: _trips, bundleResult: _bundle),
        db: LocalDb.instance,
      );

      await provider.loadTrips();
      await provider.downloadBundle('trip-001');

      expect(provider.isReady('trip-001'), isTrue);
    });
  });

  // ----------------------------------------------------------------
  // downloadBundle
  // ----------------------------------------------------------------

  group('TripProvider.downloadBundle', () {
    test('passe à done et met à jour downloadedAt sur succès', () async {
      final provider = TripProvider(
        api: FakeApiClient(bundleResult: _bundle),
        db: LocalDb.instance,
      );

      await provider.downloadBundle('trip-001');

      expect(provider.downloadStateOf('trip-001'), DownloadState.done);
      expect(provider.downloadedAtOf('trip-001'), isNotNull);
      expect(provider.downloadErrorOf('trip-001'), isNull);
    });

    test('passe à error si ApiException lors du téléchargement', () async {
      final provider = TripProvider(
        api: FakeApiClient(
          error: const ApiException('Voyage introuvable.', statusCode: 404),
        ),
        db: LocalDb.instance,
      );

      await provider.downloadBundle('trip-999');

      expect(provider.downloadStateOf('trip-999'), DownloadState.error);
      expect(provider.downloadErrorOf('trip-999'), contains('introuvable'));
    });

    test('downloadStateOf retourne idle pour un voyage jamais téléchargé', () {
      final provider = TripProvider(
        api: FakeApiClient(),
        db: LocalDb.instance,
      );
      expect(provider.downloadStateOf('trip-inconnu'), DownloadState.idle);
    });
  });
}
