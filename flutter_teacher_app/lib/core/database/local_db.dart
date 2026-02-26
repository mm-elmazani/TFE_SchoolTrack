/// Base de données locale SQLite pour le mode offline (US 2.1).
///
/// Schéma :
///   trips       — informations du voyage + timestamp de téléchargement
///   students    — élèves avec leur assignation bracelet/QR
///   checkpoints — points de contrôle du voyage
library;

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../constants.dart';
import '../../features/trips/models/offline_bundle.dart';

/// Singleton gérant la base de données SQLite locale.
class LocalDb {
  LocalDb._();
  static final LocalDb instance = LocalDb._();

  Database? _db;

  // ----------------------------------------------------------------
  // Initialisation
  // ----------------------------------------------------------------

  Future<Database> get database async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'schooltrack.db');

    return openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    /// Table des voyages téléchargés.
    await db.execute('''
      CREATE TABLE trips (
        id              TEXT PRIMARY KEY,
        destination     TEXT NOT NULL,
        date            TEXT NOT NULL,
        description     TEXT,
        status          TEXT NOT NULL,
        downloaded_at   INTEGER NOT NULL
      )
    ''');

    /// Table des élèves avec leur assignation.
    await db.execute('''
      CREATE TABLE students (
        id              TEXT NOT NULL,
        trip_id         TEXT NOT NULL,
        first_name      TEXT NOT NULL,
        last_name       TEXT NOT NULL,
        token_uid       TEXT,
        assignment_type TEXT,
        PRIMARY KEY (id, trip_id)
      )
    ''');

    /// Table des checkpoints du voyage.
    await db.execute('''
      CREATE TABLE checkpoints (
        id             TEXT NOT NULL,
        trip_id        TEXT NOT NULL,
        name           TEXT NOT NULL,
        sequence_order INTEGER NOT NULL,
        status         TEXT NOT NULL,
        PRIMARY KEY (id, trip_id)
      )
    ''');
  }

  // ----------------------------------------------------------------
  // Écriture
  // ----------------------------------------------------------------

  /// Sauvegarde un bundle offline complet dans SQLite.
  /// Supprime d'abord les données existantes pour ce voyage (re-téléchargement propre).
  Future<void> saveBundle(OfflineDataBundle bundle) async {
    final db = await database;
    final tripId = bundle.trip.id;
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.transaction((txn) async {
      // Nettoyer les données existantes pour ce voyage
      await txn.delete('checkpoints', where: 'trip_id = ?', whereArgs: [tripId]);
      await txn.delete('students', where: 'trip_id = ?', whereArgs: [tripId]);
      await txn.delete('trips', where: 'id = ?', whereArgs: [tripId]);

      // Insérer le voyage
      await txn.insert('trips', {
        'id': bundle.trip.id,
        'destination': bundle.trip.destination,
        'date': bundle.trip.date,
        'description': bundle.trip.description,
        'status': bundle.trip.status,
        'downloaded_at': now,
      });

      // Insérer les élèves en batch
      final studentBatch = txn.batch();
      for (final s in bundle.students) {
        studentBatch.insert('students', {
          'id': s.id,
          'trip_id': tripId,
          'first_name': s.firstName,
          'last_name': s.lastName,
          'token_uid': s.assignment?.tokenUid,
          'assignment_type': s.assignment?.assignmentType,
        });
      }
      await studentBatch.commit(noResult: true);

      // Insérer les checkpoints en batch
      final cpBatch = txn.batch();
      for (final cp in bundle.checkpoints) {
        cpBatch.insert('checkpoints', {
          'id': cp.id,
          'trip_id': tripId,
          'name': cp.name,
          'sequence_order': cp.sequenceOrder,
          'status': cp.status,
        });
      }
      await cpBatch.commit(noResult: true);
    });
  }

  // ----------------------------------------------------------------
  // Lecture
  // ----------------------------------------------------------------

  /// Retourne true si le voyage est téléchargé et non expiré (< 7 jours).
  Future<bool> isTripReady(String tripId) async {
    final db = await database;
    final rows = await db.query(
      'trips',
      columns: ['downloaded_at'],
      where: 'id = ?',
      whereArgs: [tripId],
    );
    if (rows.isEmpty) return false;

    final downloadedAt = rows.first['downloaded_at'] as int;
    final age = DateTime.now().millisecondsSinceEpoch - downloadedAt;
    return age < kOfflineCacheDurationMs;
  }

  /// Retourne le timestamp de téléchargement d'un voyage (null si absent).
  Future<DateTime?> getTripDownloadedAt(String tripId) async {
    final db = await database;
    final rows = await db.query(
      'trips',
      columns: ['downloaded_at'],
      where: 'id = ?',
      whereArgs: [tripId],
    );
    if (rows.isEmpty) return null;
    final ms = rows.first['downloaded_at'] as int;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// Récupère les élèves d'un voyage depuis la DB locale.
  Future<List<OfflineStudent>> getStudents(String tripId) async {
    final db = await database;
    final rows = await db.query(
      'students',
      where: 'trip_id = ?',
      whereArgs: [tripId],
      orderBy: 'last_name ASC, first_name ASC',
    );
    return rows
        .map((r) => OfflineStudent(
              id: r['id'] as String,
              firstName: r['first_name'] as String,
              lastName: r['last_name'] as String,
              assignment: r['token_uid'] != null
                  ? OfflineAssignment(
                      tokenUid: r['token_uid'] as String,
                      assignmentType: r['assignment_type'] as String,
                    )
                  : null,
            ))
        .toList();
  }

  /// Récupère les checkpoints d'un voyage depuis la DB locale.
  Future<List<OfflineCheckpoint>> getCheckpoints(String tripId) async {
    final db = await database;
    final rows = await db.query(
      'checkpoints',
      where: 'trip_id = ?',
      whereArgs: [tripId],
      orderBy: 'sequence_order ASC',
    );
    return rows
        .map((r) => OfflineCheckpoint(
              id: r['id'] as String,
              name: r['name'] as String,
              sequenceOrder: r['sequence_order'] as int,
              status: r['status'] as String,
            ))
        .toList();
  }
}
