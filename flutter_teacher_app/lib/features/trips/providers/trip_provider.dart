/// Provider gérant la liste des voyages et le téléchargement offline (US 2.1).
library;

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
  final ApiClient _api;
  final LocalDb _db;

  TripProvider({ApiClient? api, LocalDb? db})
      : _api = api ?? ApiClient(),
        _db = db ?? LocalDb.instance;

  bool _disposed = false;

  TripListState _listState = TripListState.idle;
  List<TripSummary> _trips = [];
  String? _listError;

  // État de téléchargement par trip_id
  final Map<String, DownloadState> _downloadStates = {};
  final Map<String, String> _downloadErrors = {};
  // Timestamp de téléchargement par trip_id (null = pas téléchargé)
  final Map<String, DateTime?> _downloadedAt = {};

  // ----------------------------------------------------------------
  // Getters
  // ----------------------------------------------------------------

  TripListState get listState => _listState;
  List<TripSummary> get trips => _trips;
  String? get listError => _listError;

  DownloadState downloadStateOf(String tripId) =>
      _downloadStates[tripId] ?? DownloadState.idle;

  String? downloadErrorOf(String tripId) => _downloadErrors[tripId];

  DateTime? downloadedAtOf(String tripId) => _downloadedAt[tripId];

  bool isReady(String tripId) =>
      _downloadedAt[tripId] != null &&
      downloadStateOf(tripId) != DownloadState.downloading;

  @override
  void dispose() {
    _disposed = true;
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
  Future<void> loadTrips() async {
    _listState = TripListState.loading;
    _listError = null;
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
    } on ApiException catch (e) {
      _listError = e.message;
      _listState = TripListState.error;
    } catch (e) {
      _listError = 'Erreur inattendue : $e';
      _listState = TripListState.error;
    }

    notifyListeners();
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
}
