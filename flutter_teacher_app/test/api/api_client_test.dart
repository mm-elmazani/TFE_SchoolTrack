/// Tests unitaires pour ApiClient (US 2.1).
/// Utilise un http.Client mocké pour ne pas faire de vraies requêtes réseau.
library;

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_teacher_app/core/api/api_client.dart';

// ----------------------------------------------------------------
// Helpers
// ----------------------------------------------------------------

ApiClient _clientWith(http.Client mock) =>
    ApiClient(baseUrl: 'http://test.local', client: mock);

final _tripsJson = jsonEncode([
  {
    'id': 'trip-001',
    'destination': 'Paris',
    'date': '2026-06-15',
    'status': 'PLANNED',
    'total_students': 25,
    'classes': [],
    'created_at': '2026-01-01T10:00:00',
    'updated_at': '2026-01-01T10:00:00',
  },
  {
    'id': 'trip-002',
    'destination': 'Rome',
    'date': '2026-07-01',
    'status': 'ACTIVE',
    'total_students': 18,
    'classes': [],
    'created_at': '2026-01-01T10:00:00',
    'updated_at': '2026-01-01T10:00:00',
  },
]);

final _bundleJson = jsonEncode({
  'trip': {
    'id': 'trip-001',
    'destination': 'Paris',
    'date': '2026-06-15',
    'description': null,
    'status': 'PLANNED',
  },
  'students': [
    {
      'id': 'student-001',
      'first_name': 'Jean',
      'last_name': 'Dupont',
      'assignment': {
        'token_uid': 'AA:BB:CC:DD',
        'assignment_type': 'NFC_PHYSICAL',
      },
    },
  ],
  'checkpoints': [
    {
      'id': 'cp-001',
      'name': 'Entrée',
      'sequence_order': 1,
      'status': 'DRAFT',
    },
  ],
  'generated_at': '2026-06-15T08:00:00',
});

// ----------------------------------------------------------------
// Tests getTrips
// ----------------------------------------------------------------

void main() {
  group('ApiClient.getTrips', () {
    test('retourne la liste des voyages sur réponse 200', () async {
      final client = _clientWith(
        MockClient((_) async => http.Response(_tripsJson, 200)),
      );

      final trips = await client.getTrips();

      expect(trips.length, 2);
      expect(trips[0].id, 'trip-001');
      expect(trips[0].destination, 'Paris');
      expect(trips[0].studentCount, 25);
      expect(trips[1].status, 'ACTIVE');
    });

    test('lève ApiException sur réponse 500', () async {
      final client = _clientWith(
        MockClient((_) async => http.Response('Internal Server Error', 500)),
      );

      expect(
        () => client.getTrips(),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 500),
        ),
      );
    });

    test('lève ApiException si le réseau est indisponible', () async {
      final client = _clientWith(
        MockClient((_) async => throw Exception('Network error')),
      );

      expect(() => client.getTrips(), throwsA(isA<ApiException>()));
    });

    test('retourne une liste vide si le serveur répond []', () async {
      final client = _clientWith(
        MockClient((_) async => http.Response('[]', 200)),
      );

      final trips = await client.getTrips();
      expect(trips, isEmpty);
    });
  });

  // ----------------------------------------------------------------
  // Tests getOfflineBundle
  // ----------------------------------------------------------------

  group('ApiClient.getOfflineBundle', () {
    test('retourne un bundle complet sur réponse 200', () async {
      final client = _clientWith(
        MockClient((_) async => http.Response(_bundleJson, 200)),
      );

      final bundle = await client.getOfflineBundle('trip-001');

      expect(bundle.trip.destination, 'Paris');
      expect(bundle.students.length, 1);
      expect(bundle.students[0].assignment!.tokenUid, 'AA:BB:CC:DD');
      expect(bundle.checkpoints.length, 1);
      expect(bundle.checkpoints[0].status, 'DRAFT');
    });

    test('lève ApiException avec statusCode 404 si voyage introuvable', () async {
      final client = _clientWith(
        MockClient((_) async => http.Response('Not Found', 404)),
      );

      expect(
        () => client.getOfflineBundle('trip-inconnu'),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 404),
        ),
      );
    });

    test('lève ApiException sur réponse 500', () async {
      final client = _clientWith(
        MockClient((_) async => http.Response('Server Error', 500)),
      );

      expect(
        () => client.getOfflineBundle('trip-001'),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 500),
        ),
      );
    });
  });
}
