/// Base de données locale SQLite chiffree SQLCipher pour le mode offline
/// (US 2.1 + US 2.2 + US 2.5 + US 6.3).
///
/// Schéma :
///   trips        — informations du voyage + timestamp de téléchargement
///   students     — élèves avec leur assignation bracelet/QR
///   checkpoints  — points de contrôle du voyage (créés offline, US 2.5)
///   attendances  — présences enregistrées localement (US 2.2), en attente de sync
///
/// Chiffrement : AES-256 via SQLCipher. La cle est stockee dans Android Keystore
/// via flutter_secure_storage (US 6.3).
library;

import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart' as sqflite_std;
import 'package:sqflite_sqlcipher/sqflite.dart' as sqlcipher;
import 'package:uuid/uuid.dart';
import '../constants.dart';
import '../../features/trips/models/offline_bundle.dart';
import '../../features/scan/models/attendance_record.dart';

// Re-export les types communs (identiques entre sqflite et sqflite_sqlcipher)
typedef Database = sqflite_std.Database;
typedef ConflictAlgorithm = sqflite_std.ConflictAlgorithm;

const _uuid = Uuid();

/// Singleton gérant la base de données SQLite locale.
class LocalDb {
  LocalDb._();
  static final LocalDb instance = LocalDb._();

  Database? _db;

  /// Chemin de BDD alternatif utilisé uniquement en tests (ex: inMemoryDatabasePath).
  @visibleForTesting
  static String? testDatabasePath;

  /// Ferme et réinitialise la BDD — à appeler dans tearDown() des tests uniquement.
  @visibleForTesting
  Future<void> closeForTest() async {
    await _db?.close();
    _db = null;
    testDatabasePath = null;
  }
  // ----------------------------------------------------------------
  // Initialisation
  // ----------------------------------------------------------------

  Future<Database> get database async {
    _db ??= await _open();
    return _db!;
  }

  /// Nom de la cle de chiffrement dans le Keystore Android.
  static const _dbKeyName = 'schooltrack_db_key';

  Future<Database> _open() async {
    final path = testDatabasePath ??
        join(await sqflite_std.getDatabasesPath(), 'schooltrack.db');

    // Mode test : sqflite standard (FFI, pas de chiffrement)
    if (testDatabasePath != null) {
      return sqflite_std.openDatabase(
        path,
        version: 6,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      );
    }

    // Production : sqflite_sqlcipher — chiffrement AES-256 (US 6.3)
    final password = await _getOrCreateDbKey();
    try {
      return await sqlcipher.openDatabase(
        path,
        version: 6,
        password: password,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      );
    } catch (_) {
      // Migration depuis une BDD non chiffree : supprimer et recreer
      await sqlcipher.deleteDatabase(path);
      return sqlcipher.openDatabase(
        path,
        version: 5,
        password: password,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      );
    }
  }

  /// Genere ou recupere la cle de chiffrement SQLCipher depuis le Keystore.
  Future<String> _getOrCreateDbKey() async {
    const storage = FlutterSecureStorage();
    var key = await storage.read(key: _dbKeyName);
    if (key == null) {
      final random = Random.secure();
      key = List.generate(32, (_) => random.nextInt(256))
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      await storage.write(key: _dbKeyName, value: key);
    }
    return key;
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
        classes         TEXT,
        student_count   INTEGER NOT NULL DEFAULT 0,
        downloaded_at   INTEGER NOT NULL
      )
    ''');

    /// Table des élèves avec leur assignation et données de contact.
    await db.execute('''
      CREATE TABLE students (
        id              TEXT NOT NULL,
        trip_id         TEXT NOT NULL,
        first_name      TEXT NOT NULL,
        last_name       TEXT NOT NULL,
        email           TEXT,
        phone           TEXT,
        photo_url       TEXT,
        class_name      TEXT,
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

    /// Table des présences enregistrées localement (US 2.2).
    /// Les enregistrements sont conservés jusqu'à synchronisation avec le backend.
    await db.execute('''
      CREATE TABLE attendances (
        id              TEXT PRIMARY KEY,
        trip_id         TEXT NOT NULL,
        checkpoint_id   TEXT NOT NULL,
        student_id      TEXT NOT NULL,
        scanned_at      TEXT NOT NULL,
        scan_method     TEXT NOT NULL,
        scan_sequence   INTEGER NOT NULL DEFAULT 1,
        is_manual       INTEGER NOT NULL DEFAULT 0,
        justification   TEXT,
        comment         TEXT,
        synced_at       INTEGER
      )
    ''');

    /// Index pour accélérer la détection de doublons et les requêtes de sync.
    await db.execute(
      'CREATE INDEX idx_att_checkpoint_student ON attendances(checkpoint_id, student_id)',
    );
    await db.execute(
      'CREATE INDEX idx_att_synced ON attendances(synced_at)',
    );

    /// Table d'historique des synchronisations (US 3.1 — critere #6).
    await db.execute('''
      CREATE TABLE sync_history (
        id                INTEGER PRIMARY KEY AUTOINCREMENT,
        synced_at         INTEGER NOT NULL,
        records_sent      INTEGER NOT NULL,
        records_accepted  INTEGER NOT NULL,
        records_duplicate INTEGER NOT NULL,
        records_failed    INTEGER NOT NULL DEFAULT 0,
        status            TEXT NOT NULL
      )
    ''');

    /// Table des assignations multiples par eleve (physique + QR digital).
    await db.execute('''
      CREATE TABLE student_assignments (
        student_id      TEXT NOT NULL,
        trip_id         TEXT NOT NULL,
        token_uid       TEXT NOT NULL,
        assignment_type TEXT NOT NULL,
        PRIMARY KEY (student_id, trip_id, token_uid)
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_sa_token ON student_assignments(token_uid, trip_id)',
    );
  }

  /// Migrations incrementales.
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // v1 → v2 : ajout de la table attendances (US 2.2)
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS attendances (
          id              TEXT PRIMARY KEY,
          trip_id         TEXT NOT NULL,
          checkpoint_id   TEXT NOT NULL,
          student_id      TEXT NOT NULL,
          scanned_at      TEXT NOT NULL,
          scan_method     TEXT NOT NULL,
          scan_sequence   INTEGER NOT NULL DEFAULT 1,
          is_manual       INTEGER NOT NULL DEFAULT 0,
          justification   TEXT,
          comment         TEXT,
          synced_at       INTEGER
        )
      ''');
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_att_checkpoint_student ON attendances(checkpoint_id, student_id)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_att_synced ON attendances(synced_at)',
      );
    }
    // v3 → v4 : ajout de la table sync_history (US 3.1)
    if (oldVersion < 4) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS sync_history (
          id                INTEGER PRIMARY KEY AUTOINCREMENT,
          synced_at         INTEGER NOT NULL,
          records_sent      INTEGER NOT NULL,
          records_accepted  INTEGER NOT NULL,
          records_duplicate INTEGER NOT NULL,
          records_failed    INTEGER NOT NULL DEFAULT 0,
          status            TEXT NOT NULL
        )
      ''');
    }
    // v4 → v5 : table student_assignments (support double assignation physique + QR digital)
    if (oldVersion < 5) {

      await db.execute('''
        CREATE TABLE IF NOT EXISTS student_assignments (
          student_id      TEXT NOT NULL,
          trip_id         TEXT NOT NULL,
          token_uid       TEXT NOT NULL,
          assignment_type TEXT NOT NULL,
          PRIMARY KEY (student_id, trip_id, token_uid)
        )
      ''');
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_sa_token ON student_assignments(token_uid, trip_id)',
      );
    }
    // v5 → v6 : ajout email, phone, photo_url, class_name sur students + classes/student_count sur trips
    if (oldVersion < 6) {
      await db.execute('ALTER TABLE students ADD COLUMN email TEXT');
      await db.execute('ALTER TABLE students ADD COLUMN phone TEXT');
      await db.execute('ALTER TABLE students ADD COLUMN photo_url TEXT');
      await db.execute('ALTER TABLE students ADD COLUMN class_name TEXT');
      await db.execute('ALTER TABLE trips ADD COLUMN classes TEXT');
      await db.execute('ALTER TABLE trips ADD COLUMN student_count INTEGER NOT NULL DEFAULT 0');
    }
  }

  // ----------------------------------------------------------------
  // Écriture — bundles offline
  // ----------------------------------------------------------------

  /// Sauvegarde un bundle offline complet dans SQLite.
  /// Supprime d'abord les données existantes pour ce voyage (re-téléchargement propre).
  /// Les présences déjà enregistrées pour ce voyage sont préservées.
  Future<void> saveBundle(OfflineDataBundle bundle) async {
    final db = await database;
    final tripId = bundle.trip.id;
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.transaction((txn) async {
      // Nettoyer les données existantes pour ce voyage (sauf attendances)
      await txn.delete('student_assignments', where: 'trip_id = ?', whereArgs: [tripId]);
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
        'classes': jsonEncode(bundle.trip.classes),
        'student_count': bundle.trip.studentCount,
        'downloaded_at': now,
      });

      // Insérer les élèves en batch (REPLACE pour idempotence — cas de re-téléchargement)
      final studentBatch = txn.batch();
      for (final s in bundle.students) {
        studentBatch.insert(
          'students',
          {
            'id': s.id,
            'trip_id': tripId,
            'first_name': s.firstName,
            'last_name': s.lastName,
            'email': s.email,
            'phone': s.phone,
            'photo_url': s.photoUrl,
            'class_name': s.className,
            'token_uid': s.assignment?.tokenUid,
            'assignment_type': s.assignment?.assignmentType,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await studentBatch.commit(noResult: true);

      // Insérer toutes les assignations dans student_assignments
      final assignBatch = txn.batch();
      for (final s in bundle.students) {
        for (final a in s.assignments) {
          assignBatch.insert(
            'student_assignments',
            {
              'student_id': s.id,
              'trip_id': tripId,
              'token_uid': a.tokenUid,
              'assignment_type': a.assignmentType,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
      await assignBatch.commit(noResult: true);

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
  // Écriture — présences (US 2.2)
  // ----------------------------------------------------------------

  /// Enregistre une présence dans SQLite.
  /// Retourne le numéro de séquence (1 = premier scan, 2 = deuxième scan du même élève, etc.).
  Future<int> saveAttendance(AttendanceRecord record) async {
    final db = await database;

    // Calcul du scan_sequence : combien de fois cet élève a déjà été scanné à ce checkpoint ?
    final existing = await db.query(
      'attendances',
      columns: ['id'],
      where: 'checkpoint_id = ? AND student_id = ?',
      whereArgs: [record.checkpointId, record.studentId],
    );
    final sequence = existing.length + 1;

    await db.insert('attendances', {
      'id': record.id,
      'trip_id': record.tripId,
      'checkpoint_id': record.checkpointId,
      'student_id': record.studentId,
      'scanned_at': record.scannedAt.toIso8601String(),
      'scan_method': record.scanMethod,
      'scan_sequence': sequence,
      'is_manual': record.isManual ? 1 : 0,
      'justification': record.justification,
      'comment': record.comment,
      'synced_at': null,
    });

    return sequence;
  }

  /// Vérifie si un élève a déjà été scanné à ce checkpoint.
  /// Retourne le nombre de scans précédents (0 = premier scan).
  Future<int> countAttendances(String checkpointId, String studentId) async {
    final db = await database;
    final rows = await db.query(
      'attendances',
      columns: ['id'],
      where: 'checkpoint_id = ? AND student_id = ?',
      whereArgs: [checkpointId, studentId],
    );
    return rows.length;
  }

  /// Retourne toutes les présences d'un checkpoint (triées par date de scan).
  Future<List<AttendanceRecord>> getAttendancesByCheckpoint(
    String checkpointId,
  ) async {
    final db = await database;
    final rows = await db.query(
      'attendances',
      where: 'checkpoint_id = ?',
      whereArgs: [checkpointId],
      orderBy: 'scanned_at ASC',
    );
    return rows.map(_rowToAttendance).toList();
  }

  /// Retourne les présences non encore synchronisées (synced_at IS NULL).
  Future<List<AttendanceRecord>> getPendingAttendances() async {
    final db = await database;
    final rows = await db.query(
      'attendances',
      where: 'synced_at IS NULL',
      orderBy: 'scanned_at ASC',
    );
    return rows.map(_rowToAttendance).toList();
  }

  /// Marque une liste de présences comme synchronisées.
  Future<void> markAttendancesSynced(List<String> ids) async {
    if (ids.isEmpty) return;
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final placeholders = List.filled(ids.length, '?').join(',');
    await db.rawUpdate(
      'UPDATE attendances SET synced_at = ? WHERE id IN ($placeholders)',
      [now, ...ids],
    );
  }

  AttendanceRecord _rowToAttendance(Map<String, dynamic> r) {
    return AttendanceRecord(
      id: r['id'] as String,
      tripId: r['trip_id'] as String,
      checkpointId: r['checkpoint_id'] as String,
      studentId: r['student_id'] as String,
      scannedAt: DateTime.parse(r['scanned_at'] as String),
      scanMethod: r['scan_method'] as String,
      scanSequence: r['scan_sequence'] as int,
      isManual: (r['is_manual'] as int) == 1,
      justification: r['justification'] as String?,
      comment: r['comment'] as String?,
      syncedAt: r['synced_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(r['synced_at'] as int)
          : null,
    );
  }

  // ----------------------------------------------------------------
  // Lecture — voyages
  // ----------------------------------------------------------------

  /// Retourne les voyages stockés localement (fallback offline).
  /// Utilisé quand le réseau est indisponible au démarrage.
  Future<List<TripSummary>> getLocalTrips() async {
    final db = await database;
    final rows = await db.query('trips', orderBy: 'date ASC');
    return rows
        .map((r) => TripSummary(
              id: r['id'] as String,
              destination: r['destination'] as String,
              date: r['date'] as String,
              status: r['status'] as String,
              studentCount: 0, // non stocké localement
            ))
        .toList();
  }

  /// Retourne les infos offline d'un voyage stocké localement.
  Future<OfflineTripInfo?> getTripInfo(String tripId) async {
    final db = await database;
    final rows = await db.query('trips', where: 'id = ?', whereArgs: [tripId]);
    if (rows.isEmpty) return null;
    final r = rows.first;
    final classesJson = r['classes'] as String?;
    final classes = classesJson != null
        ? List<String>.from(jsonDecode(classesJson) as List)
        : <String>[];
    return OfflineTripInfo(
      id: r['id'] as String,
      destination: r['destination'] as String,
      date: r['date'] as String,
      description: r['description'] as String?,
      status: r['status'] as String,
      classes: classes,
      studentCount: r['student_count'] as int? ?? 0,
    );
  }

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

  // ----------------------------------------------------------------
  // Lecture — élèves
  // ----------------------------------------------------------------

  /// Récupère les élèves d'un voyage depuis la DB locale.
  Future<List<OfflineStudent>> getStudents(String tripId) async {
    final db = await database;
    final rows = await db.query(
      'students',
      where: 'trip_id = ?',
      whereArgs: [tripId],
      orderBy: 'last_name ASC, first_name ASC',
    );
    return rows.map(_rowToStudent).toList();
  }

  /// Résout un UUID d'élève en OfflineStudent pour un voyage donné.
  /// Utilisé par HybridIdentityReader pour les QR codes digitaux (préfixe QRD-).
  Future<OfflineStudent?> resolveStudentById(
      String studentId, String tripId) async {
    final db = await database;
    final rows = await db.query(
      'students',
      where: 'id = ? AND trip_id = ?',
      whereArgs: [studentId, tripId],
    );
    if (rows.isEmpty) return null;
    return _rowToStudent(rows.first);
  }

  /// Résout un UID de token en OfflineStudent pour un voyage donné.
  /// Cherche dans student_assignments (physique + QR digital).
  /// Utilisé par HybridIdentityReader après scan NFC/QR.
  Future<OfflineStudent?> resolveUid(String uid, String tripId) async {
    final db = await database;

    // Chercher dans student_assignments (supporte double assignation)
    final assignRows = await db.query(
      'student_assignments',
      where: 'token_uid = ? AND trip_id = ?',
      whereArgs: [uid, tripId],
    );

    if (assignRows.isNotEmpty) {
      final studentId = assignRows.first['student_id'] as String;
      final studentRows = await db.query(
        'students',
        where: 'id = ? AND trip_id = ?',
        whereArgs: [studentId, tripId],
      );
      if (studentRows.isNotEmpty) {
        final s = _rowToStudent(studentRows.first);
        // Remplacer l'assignment par celui résolu depuis student_assignments
        return OfflineStudent(
          id: s.id,
          firstName: s.firstName,
          lastName: s.lastName,
          email: s.email,
          phone: s.phone,
          photoUrl: s.photoUrl,
          className: s.className,
          assignment: OfflineAssignment(
            tokenUid: uid,
            assignmentType: assignRows.first['assignment_type'] as String,
          ),
          assignments: s.assignments,
        );
      }
    }

    // Fallback : ancienne colonne token_uid dans students (rétro-compat)
    final rows = await db.query(
      'students',
      where: 'token_uid = ? AND trip_id = ?',
      whereArgs: [uid, tripId],
    );
    if (rows.isEmpty) return null;
    return _rowToStudent(rows.first);
  }

  OfflineStudent _rowToStudent(Map<String, dynamic> r) {
    return OfflineStudent(
      id: r['id'] as String,
      firstName: r['first_name'] as String,
      lastName: r['last_name'] as String,
      email: r['email'] as String?,
      phone: r['phone'] as String?,
      photoUrl: r['photo_url'] as String?,
      className: r['class_name'] as String?,
      assignment: r['token_uid'] != null
          ? OfflineAssignment(
              tokenUid: r['token_uid'] as String,
              assignmentType: r['assignment_type'] as String,
            )
          : null,
    );
  }

  // ----------------------------------------------------------------
  // Lecture — checkpoints
  // ----------------------------------------------------------------

  /// Récupère les checkpoints d'un voyage depuis la DB locale.
  Future<List<OfflineCheckpoint>> getCheckpoints(String tripId) async {
    final db = await database;
    final rows = await db.query(
      'checkpoints',
      where: 'trip_id = ?',
      whereArgs: [tripId],
      orderBy: 'sequence_order ASC',
    );
    return rows.map(_rowToCheckpoint).toList();
  }

  /// Récupère un checkpoint par son ID (null si absent).
  Future<OfflineCheckpoint?> getCheckpointById(String checkpointId) async {
    final db = await database;
    final rows = await db.query(
      'checkpoints',
      where: 'id = ?',
      whereArgs: [checkpointId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _rowToCheckpoint(rows.first);
  }

  // ----------------------------------------------------------------
  // Écriture — checkpoints terrain (US 2.5)
  // ----------------------------------------------------------------

  /// Crée un nouveau checkpoint en SQLite local avec statut DRAFT.
  ///
  /// Génère un UUID client, calcule le prochain sequence_order,
  /// et retourne l'objet créé. Offline-first : la synchronisation
  /// avec le backend se fera via US 3.1.
  Future<OfflineCheckpoint> createCheckpoint({
    required String tripId,
    required String name,
  }) async {
    final db = await database;
    final id = _uuid.v4();

    // Calcul du prochain sequence_order pour ce voyage
    final rows = await db.query(
      'checkpoints',
      columns: ['sequence_order'],
      where: 'trip_id = ?',
      whereArgs: [tripId],
      orderBy: 'sequence_order DESC',
      limit: 1,
    );
    final nextOrder =
        rows.isEmpty ? 1 : (rows.first['sequence_order'] as int) + 1;

    await db.insert('checkpoints', {
      'id': id,
      'trip_id': tripId,
      'name': name,
      'sequence_order': nextOrder,
      'status': 'DRAFT',
    });

    return OfflineCheckpoint(
      id: id,
      name: name,
      sequenceOrder: nextOrder,
      status: 'DRAFT',
    );
  }

  /// Passe le statut d'un checkpoint de DRAFT à ACTIVE dans SQLite local.
  ///
  /// Appelé au premier scan réussi (US 2.5). La mise à jour sera
  /// synchronisée avec le backend lors de la synchronisation (US 3.1).
  Future<void> activateCheckpoint(String checkpointId) async {
    final db = await database;
    await db.update(
      'checkpoints',
      {'status': 'ACTIVE'},
      where: 'id = ?',
      whereArgs: [checkpointId],
    );
  }

  /// Passe le statut d'un checkpoint ACTIVE à CLOSED dans SQLite local (US 2.7).
  ///
  /// Un checkpoint CLOSED est en lecture seule : aucun nouveau scan n'est possible.
  /// La mise à jour sera propagée au backend via le call best-effort de l'ApiClient.
  Future<void> closeCheckpoint(String checkpointId) async {
    final db = await database;
    await db.update(
      'checkpoints',
      {'status': 'CLOSED'},
      where: 'id = ?',
      whereArgs: [checkpointId],
    );
  }

  // ----------------------------------------------------------------
  // Historique de synchronisation (US 3.1)
  // ----------------------------------------------------------------

  /// Enregistre une entree dans l'historique de synchronisation.
  Future<void> insertSyncHistory({
    required int recordsSent,
    required int recordsAccepted,
    required int recordsDuplicate,
    required int recordsFailed,
    required String status,
  }) async {
    final db = await database;
    await db.insert('sync_history', {
      'synced_at': DateTime.now().millisecondsSinceEpoch,
      'records_sent': recordsSent,
      'records_accepted': recordsAccepted,
      'records_duplicate': recordsDuplicate,
      'records_failed': recordsFailed,
      'status': status,
    });
  }

  /// Retourne l'historique des synchronisations (plus recentes en premier).
  Future<List<SyncHistoryEntry>> getSyncHistory({int limit = 50}) async {
    final db = await database;
    final rows = await db.query(
      'sync_history',
      orderBy: 'synced_at DESC',
      limit: limit,
    );
    return rows.map((r) => SyncHistoryEntry(
      id: r['id'] as int,
      syncedAt: DateTime.fromMillisecondsSinceEpoch(r['synced_at'] as int),
      recordsSent: r['records_sent'] as int,
      recordsAccepted: r['records_accepted'] as int,
      recordsDuplicate: r['records_duplicate'] as int,
      recordsFailed: r['records_failed'] as int,
      status: r['status'] as String,
    )).toList();
  }

  OfflineCheckpoint _rowToCheckpoint(Map<String, dynamic> r) {
    return OfflineCheckpoint(
      id: r['id'] as String,
      name: r['name'] as String,
      sequenceOrder: r['sequence_order'] as int,
      status: r['status'] as String,
    );
  }
}

/// Entree dans l'historique de synchronisation (US 3.1).
class SyncHistoryEntry {
  final int id;
  final DateTime syncedAt;
  final int recordsSent;
  final int recordsAccepted;
  final int recordsDuplicate;
  final int recordsFailed;
  final String status;

  const SyncHistoryEntry({
    required this.id,
    required this.syncedAt,
    required this.recordsSent,
    required this.recordsAccepted,
    required this.recordsDuplicate,
    required this.recordsFailed,
    required this.status,
  });

  bool get isSuccess => status == 'SUCCESS';
}
