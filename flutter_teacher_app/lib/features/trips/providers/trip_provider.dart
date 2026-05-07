/// Provider gérant la liste des voyages et le téléchargement offline (US 2.1).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import '../../../core/api/api_client.dart';
import '../../../core/database/local_db.dart';
import '../models/offline_bundle.dart';

/// États possibles du chargement de la liste des voyages.
enum TripListState { idle, loading, ready, error }

/// État de téléchargement d'un voyage spécifique.
enum DownloadState { idle, downloading, done, error }

/// Provider central pour la liste des voyages et le téléchargement offline.
class TripProvider extends ChangeNotifier {
  /// Intervalle entre deux auto-refresh de la liste des voyages.
  /// Une minute = compromis entre fraicheur des donnees et batterie.
  static const Duration kAutoRefreshInterval = Duration(seconds: 60);

  final ApiClient _api;
  final LocalDb _db;

  TripProvider({ApiClient? api, LocalDb? db})
      : _api = api ?? ApiClient(),
        _db = db ?? LocalDb.instance;

  bool _disposed = false;

  TripListState _listState = TripListState.idle;
  List<TripSummary> _trips = [];
  String? _listError;
  bool _isOffline = false;

  // État de téléchargement par trip_id
  final Map<String, DownloadState> _downloadStates = {};
  final Map<String, String> _downloadErrors = {};
  // Timestamp de téléchargement par trip_id (null = pas téléchargé)
  final Map<String, DateTime?> _downloadedAt = {};

  // Timer d'auto-refresh de la liste des voyages
  Timer? _autoRefreshTimer;

  // ----------------------------------------------------------------
  // Getters
  // ----------------------------------------------------------------

  TripListState get listState => _listState;
  List<TripSummary> get trips => _trips;
  String? get listError => _listError;
  bool get isOffline => _isOffline;

  DownloadState downloadStateOf(String tripId) =>
      _downloadStates[tripId] ?? DownloadState.idle;

  String? downloadErrorOf(String tripId) => _downloadErrors[tripId];

  DateTime? downloadedAtOf(String tripId) => _downloadedAt[tripId];

  bool isReady(String tripId) =>
      _downloadedAt[tripId] != null &&
      downloadStateOf(tripId) != DownloadState.downloading;

  /// Indique si un download de bundle est actuellement en cours
  /// (utilise par l'auto-refresh pour eviter les courses).
  bool get _hasActiveDownload =>
      _downloadStates.values.any((s) => s == DownloadState.downloading);

  @override
  void dispose() {
    _disposed = true;
    stopAutoRefresh();
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  // ----------------------------------------------------------------
  // Chargement de la liste des voyages
  // ----------------------------------------------------------------

  /// Charge la liste des voyages depuis l'API.
  /// En cas d'échec réseau, bascule en mode offline avec les données SQLite locales.
  /// No-op si un chargement est deja en cours (evite les races avec l'auto-refresh).
  Future<void> loadTrips() async {
    if (_listState == TripListState.loading) return;

    _listState = TripListState.loading;
    _listError = null;
    _isOffline = false;
    notifyListeners();

    try {
      _trips = await _api.getTrips();
      _listState = TripListState.ready;

      // Vérifier quels voyages sont déjà téléchargés
      for (final trip in _trips) {
        _downloadedAt[trip.id] = await _db.getTripDownloadedAt(trip.id);
        final ready = await _db.isTripReady(trip.id);
        if (!ready) _downloadedAt[trip.id] = null;
      }
    } on ApiException {
      // Réseau indisponible → fallback sur les voyages stockés localement
      await _loadFromLocalDb();
    } catch (_) {
      await _loadFromLocalDb();
    }

    notifyListeners();
  }

  /// Charge les voyages depuis SQLite quand le réseau est indisponible.
  Future<void> _loadFromLocalDb() async {
    final localTrips = await _db.getLocalTrips();
    if (localTrips.isNotEmpty) {
      _trips = localTrips;
      _isOffline = true;
      _listState = TripListState.ready;
      // Marquer les voyages déjà téléchargés
      for (final trip in _trips) {
        _downloadedAt[trip.id] = await _db.getTripDownloadedAt(trip.id);
        final ready = await _db.isTripReady(trip.id);
        if (!ready) _downloadedAt[trip.id] = null;
      }
    } else {
      _listError = 'Réseau indisponible et aucun voyage en cache.';
      _listState = TripListState.error;
    }
  }

  // ----------------------------------------------------------------
  // Téléchargement du bundle offline
  // ----------------------------------------------------------------

  /// Télécharge et sauvegarde le bundle offline d'un voyage dans SQLite.
  Future<void> downloadBundle(String tripId) async {
    _downloadStates[tripId] = DownloadState.downloading;
    _downloadErrors.remove(tripId);
    notifyListeners();

    try {
      final bundle = await _api.getOfflineBundle(tripId);
      await _db.saveBundle(bundle);

      _downloadedAt[tripId] = DateTime.now();
      _downloadStates[tripId] = DownloadState.done;
    } on ApiException catch (e) {
      _downloadErrors[tripId] = e.message;
      _downloadStates[tripId] = DownloadState.error;
    } catch (e) {
      _downloadErrors[tripId] = 'Erreur inattendue : $e';
      _downloadStates[tripId] = DownloadState.error;
    }

    notifyListeners();
  }

  // ----------------------------------------------------------------
  // Auto-refresh periodique de la liste des voyages
  // ----------------------------------------------------------------

  /// Active l'auto-refresh : `loadTrips()` est rappele toutes les
  /// [kAutoRefreshInterval]. Le tick est skip si un chargement est
  /// en cours ou si un download de bundle est actif (evite les races).
  ///
  /// Appel idempotent : si l'auto-refresh tourne deja, le timer existant
  /// est annule et redemarre proprement.
  void startAutoRefresh({Duration? interval}) {
    stopAutoRefresh();
    _autoRefreshTimer = Timer.periodic(
      interval ?? kAutoRefreshInterval,
      (_) => _autoRefreshTick(),
    );
  }

  /// Arrete l'auto-refresh.
  void stopAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = null;
  }

  /// Indique si l'auto-refresh est actuellement actif (utile pour les tests).
  @visibleForTesting
  bool get isAutoRefreshActive => _autoRefreshTimer?.isActive ?? false;

  Future<void> _autoRefreshTick() async {
    // Skip si l'utilisateur est en train de telecharger un bundle
    // ou si un autre chargement est deja en cours.
    if (_disposed) return;
    if (_listState == TripListState.loading) return;
    if (_hasActiveDownload) return;

    await loadTrips();
  }
}
