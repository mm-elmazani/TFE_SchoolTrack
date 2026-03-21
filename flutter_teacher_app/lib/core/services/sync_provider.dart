/// Provider de synchronisation (US 3.1).
///
/// Gere l'etat de sync (idle/syncing/synced/error), le compteur de presences
/// en attente, et declenche la sync automatiquement au retour du reseau
/// ou periodiquement quand des presences sont en attente.
library;

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'sync_service.dart';

/// Etats possibles de la synchronisation.
enum SyncStatus { idle, syncing, synced, error, offline }

/// Provider exposant l'etat de synchronisation a l'UI.
class SyncProvider extends ChangeNotifier {
  final SyncService _service;
  final Connectivity _connectivity;

  SyncStatus _status = SyncStatus.idle;
  int _pendingCount = 0;
  DateTime? _lastSyncAt;
  String? _lastError;
  SyncReport? _lastReport;
  String? _deviceId;

  /// Verrou anti-sync concurrente.
  bool _isSyncing = false;

  /// Timer periodique pour re-tenter la sync quand des presences sont en attente.
  Timer? _periodicTimer;

  /// Abonnement aux changements de connectivite.
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  SyncProvider({SyncService? service, Connectivity? connectivity})
      : _service = service ?? SyncService(),
        _connectivity = connectivity ?? Connectivity();

  // -- Getters --
  SyncStatus get status => _status;
  int get pendingCount => _pendingCount;
  DateTime? get lastSyncAt => _lastSyncAt;
  String? get lastError => _lastError;
  SyncReport? get lastReport => _lastReport;
  bool get hasPending => _pendingCount > 0;

  /// Demarre l'auto-sync : ecoute connectivity + timer periodique.
  /// Appeler apres une authentification reussie.
  Future<void> startAutoSync() async {
    await _loadDeviceId();
    await refreshPendingCount();

    // Ecouter les changements de connectivite
    _connectivitySub?.cancel();
    _connectivitySub = _connectivity.onConnectivityChanged.listen((results) {
      final hasNetwork = results.any((r) => r != ConnectivityResult.none);
      if (hasNetwork && _pendingCount > 0) {
        // Debounce 2 secondes (le reseau peut ne pas etre pret immediatement)
        Future.delayed(const Duration(seconds: 2), () => syncNow());
      }
    });

    // Timer periodique : tenter la sync toutes les 30s si des presences sont en attente
    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_pendingCount > 0 && !_isSyncing) {
        syncNow();
      }
    });
  }

  /// Arrete l'auto-sync. Appeler au logout.
  void stopAutoSync() {
    _connectivitySub?.cancel();
    _connectivitySub = null;
    _periodicTimer?.cancel();
    _periodicTimer = null;
  }

  /// Rafraichit le compteur de presences en attente depuis SQLite.
  Future<void> refreshPendingCount() async {
    _pendingCount = await _service.getPendingCount();
    notifyListeners();
  }

  /// Declenche une synchronisation manuelle.
  Future<void> syncNow() async {
    if (_isSyncing) return; // Pas de double sync
    _isSyncing = true;
    _status = SyncStatus.syncing;
    _lastError = null;
    notifyListeners();

    try {
      final report = await _service.syncPendingAttendances(
        deviceId: _deviceId ?? 'unknown',
      );
      _lastReport = report;

      if (report.nothingToSync) {
        _status = SyncStatus.idle;
      } else if (report.isFullSuccess) {
        _status = SyncStatus.synced;
        _lastSyncAt = DateTime.now();
      } else if (report.hadNetworkError) {
        _status = SyncStatus.offline;
        _lastError = 'Pas de connexion reseau';
      } else {
        _status = SyncStatus.error;
        _lastError = '${report.totalFailed} presences non synchronisees';
      }

      await refreshPendingCount();
    } catch (e) {
      _status = SyncStatus.error;
      _lastError = e.toString();
      notifyListeners();
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  /// Genere ou recupere un device_id unique stocke en flutter_secure_storage.
  Future<void> _loadDeviceId() async {
    const storage = FlutterSecureStorage();
    const key = 'schooltrack_device_id';
    _deviceId = await storage.read(key: key);
    if (_deviceId == null) {
      _deviceId = 'device-${DateTime.now().millisecondsSinceEpoch}';
      await storage.write(key: key, value: _deviceId!);
    }
  }

  @override
  void dispose() {
    stopAutoSync();
    super.dispose();
  }
}
