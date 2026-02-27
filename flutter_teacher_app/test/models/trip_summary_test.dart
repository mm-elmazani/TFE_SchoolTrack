/// Tests unitaires pour TripSummary.fromJson (US 2.1).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_teacher_app/features/trips/models/offline_bundle.dart';

void main() {
  group('TripSummary.fromJson', () {
    test('parse tous les champs via total_students', () {
      final trip = TripSummary.fromJson({
        'id': 'trip-001',
        'destination': 'Paris',
        'date': '2026-06-15',
        'status': 'PLANNED',
        'total_students': 25,
      });

      expect(trip.id, 'trip-001');
      expect(trip.destination, 'Paris');
      expect(trip.date, '2026-06-15');
      expect(trip.status, 'PLANNED');
      expect(trip.studentCount, 25);
    });

    test('fallback sur student_count si total_students absent', () {
      final trip = TripSummary.fromJson({
        'id': 'trip-002',
        'destination': 'Rome',
        'date': '2026-07-01',
        'status': 'ACTIVE',
        'student_count': 30,
      });

      expect(trip.studentCount, 30);
    });

    test('retourne 0 si aucun champ de comptage présent', () {
      final trip = TripSummary.fromJson({
        'id': 'trip-003',
        'destination': 'Berlin',
        'date': '2026-08-01',
        'status': 'PLANNED',
      });

      expect(trip.studentCount, 0);
    });

    test('total_students est prioritaire sur student_count', () {
      final trip = TripSummary.fromJson({
        'id': 'trip-004',
        'destination': 'Madrid',
        'date': '2026-09-01',
        'status': 'PLANNED',
        'total_students': 20,
        'student_count': 10,
      });

      expect(trip.studentCount, 20);
    });

    test('statuts reconnus : PLANNED, ACTIVE, COMPLETED, ARCHIVED', () {
      for (final status in ['PLANNED', 'ACTIVE', 'COMPLETED', 'ARCHIVED']) {
        final trip = TripSummary.fromJson({
          'id': 'trip-x',
          'destination': 'Test',
          'date': '2026-01-01',
          'status': status,
          'total_students': 0,
        });
        expect(trip.status, status);
      }
    });
  });
}
