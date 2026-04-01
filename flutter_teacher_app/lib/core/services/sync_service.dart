/// Service de synchronisation SQLite → backend (US 3.1).
///
/// Lit les presences en attente (synced_at IS NULL), les envoie au backend
/// par batch de 500 max, et marque les acceptees + doublons comme synchronisees.
library;

import '../api/api_client.dart';
import '../database/local_db.dart';
import '../../features/scan/models/attendance_record.dart';

/// Taille maximale d'un batch (contrainte backend).
const int _maxBatchSize = 500;

/// Resultat global d'une synchronisation.
class SyncReport {
  final int totalSent;
  final int totalAccepted;
  final int totalDuplicate;
  final int totalFailed;
  final bool hadNetworkError;

  const SyncReport({
    this.totalSent = 0,
    this.totalAccepted = 0,
    this.totalDuplicate = 0,
    this.totalFailed = 0,
    this.hadNetworkError = false,
  });

  bool get isFullSuccess => totalFailed == 0 && !hadNetworkError;
  bool get nothingToSync => totalSent == 0;
}

/// Service stateless qui orchestre la synchronisation.
class SyncService {
  final ApiClient _api;
  final LocalDb _db;

  SyncService({ApiClient? api, LocalDb? db})
      : _api = api ?? ApiClient(),
        _db = db ?? LocalDb.instance;

  /// Synchronise toutes les presences en attente.
  ///
  /// Les presences sont envoyees par batch de [_maxBatchSize].
  /// Chaque batch reussi est marque synced immediatement (resilient aux echecs partiels).
  Future<SyncReport> syncPendingAttendances({required String deviceId}) async {
    final pending = await _db.getPendingAttendances();
    if (pending.isEmpty) {
      return const SyncReport();
    }

    int totalSent = 0;
    int totalAccepted = 0;
    int totalDuplicate = 0;
    int totalFailed = 0;
    bool hadNetworkError = false;

    // Chunker en batches de 500
    final batches = _chunk(pending, _maxBatchSize);

    for (final batch in batches) {
      final scansJson = batch.map(_toScanJson).toList();
      totalSent += batch.length;

      try {
        final result = await _api.syncAttendances(
          scans: scansJson,
          deviceId: deviceId,
        );

        if (result == null) {
          // Hors-ligne → on arrete, les batches suivants echoueraient aussi
          totalFailed += batch.length;
          hadNetworkError = true;
          break;
        }

        totalAccepted += result.totalInserted;
        totalDuplicate += result.duplicate.length;

        // Marquer accepted + duplicate + rejected comme synced
        // Les rejected (checkpoint supprime, etc.) ne seront jamais acceptes
        // et ne doivent pas etre renvoyes en boucle.
        final syncedIds = <String>[
          ...result.accepted,
          ...result.duplicate,
          ...result.rejected,
        ];
        if (syncedIds.isNotEmpty) {
          await _db.markAttendancesSynced(syncedIds);
        }

        // Si des scans du batch n'apparaissent dans aucune liste
        final processedSet = {
          ...result.accepted,
          ...result.duplicate,
          ...result.rejected,
        };
        final unprocessed = batch.where((r) => !processedSet.contains(r.id)).length;
        totalFailed += unprocessed;
      } on ApiException {
        // Erreur API (422, etc.) → ce batch echoue, on continue les suivants
        totalFailed += batch.length;
      }
    }

    final report = SyncReport(
      totalSent: totalSent,
      totalAccepted: totalAccepted,
      totalDuplicate: totalDuplicate,
      totalFailed: totalFailed,
      hadNetworkError: hadNetworkError,
    );

    // Enregistrer dans l'historique de synchronisation (US 3.1 critere #6)
    if (!report.nothingToSync) {
      final status = report.isFullSuccess
          ? 'SUCCESS'
          : report.hadNetworkError
              ? 'OFFLINE'
              : 'PARTIAL';
      await _db.insertSyncHistory(
        recordsSent: report.totalSent,
        recordsAccepted: report.totalAccepted,
        recordsDuplicate: report.totalDuplicate,
        recordsFailed: report.totalFailed,
        status: status,
      );
    }

    return report;
  }

  /// Retourne le nombre de presences en attente de synchronisation.
  Future<int> getPendingCount() async {
    final pending = await _db.getPendingAttendances();
    return pending.length;
  }

  /// Convertit un AttendanceRecord en JSON pour le backend.
  Map<String, dynamic> _toScanJson(AttendanceRecord r) {
    return {
      'client_uuid': r.id,
      'student_id': r.studentId,
      'checkpoint_id': r.checkpointId,
      'trip_id': r.tripId,
      'scanned_at': r.scannedAt.toIso8601String(),
      'scan_method': r.scanMethod,
      'scan_sequence': r.scanSequence,
      'is_manual': r.isManual,
      if (r.justification != null) 'justification': r.justification,
      if (r.comment != null) 'comment': r.comment,
    };
  }

  /// Decoupe une liste en sous-listes de taille max [size].
  List<List<T>> _chunk<T>(List<T> list, int size) {
    final chunks = <List<T>>[];
    for (var i = 0; i < list.length; i += size) {
      final end = (i + size < list.length) ? i + size : list.length;
      chunks.add(list.sublist(i, end));
    }
    return chunks;
  }
}
