import 'package:flutter/foundation.dart';
import '../../../core/api/api_client.dart';

/// Modèle d'un voyage retourné par l'API.
class Trip {
  final String id;
  final String destination;
  final DateTime date;
  final String? description;
  final String status;
  final int totalStudents;

  const Trip({
    required this.id,
    required this.destination,
    required this.date,
    this.description,
    required this.status,
    required this.totalStudents,
  });

  factory Trip.fromJson(Map<String, dynamic> json) {
    return Trip(
      id: json['id'] as String,
      destination: json['destination'] as String,
      date: DateTime.parse(json['date'] as String),
      description: json['description'] as String?,
      status: json['status'] as String,
      totalStudents: (json['total_students'] as int?) ?? 0,
    );
  }
}

/// Modèle d'une classe scolaire (utilisé dans le formulaire voyage).
class SchoolClass {
  final String id;
  final String name;
  final String? year;
  final int nbStudents;

  const SchoolClass({
    required this.id,
    required this.name,
    this.year,
    required this.nbStudents,
  });

  factory SchoolClass.fromJson(Map<String, dynamic> json) {
    return SchoolClass(
      id: json['id'] as String,
      name: json['name'] as String,
      year: json['year'] as String?,
      nbStudents: (json['nb_students'] as int?) ?? 0,
    );
  }

  /// Libellé affiché dans la liste de sélection
  String get displayName => year != null ? '$name ($year)' : name;
}

/// États possibles pour les opérations asynchrones
enum TripLoadState { idle, loading, success, error }

/// Provider gérant la liste des voyages et les opérations CRUD (US 1.2).
class TripProvider extends ChangeNotifier {
  final ApiClient _apiClient;

  TripProvider({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  // --- État liste ---
  TripLoadState _listState = TripLoadState.idle;
  List<Trip> _trips = [];
  String? _listError;

  // --- État opération (create/update/delete) ---
  TripLoadState _opState = TripLoadState.idle;
  String? _opError;

  // --- Classes disponibles pour le formulaire ---
  List<SchoolClass> _classes = [];

  // --- Filtres ---
  String _searchQuery = '';
  String _statusFilter = 'ALL';

  // --- Getters ---
  TripLoadState get listState => _listState;
  TripLoadState get opState => _opState;
  String? get listError => _listError;
  String? get opError => _opError;
  List<SchoolClass> get classes => _classes;
  String get searchQuery => _searchQuery;
  String get statusFilter => _statusFilter;

  /// Voyages filtrés selon la recherche et le statut sélectionné
  List<Trip> get filteredTrips {
    return _trips.where((t) {
      final matchSearch = _searchQuery.isEmpty ||
          t.destination.toLowerCase().contains(_searchQuery.toLowerCase());
      final matchStatus = _statusFilter == 'ALL' || t.status == _statusFilter;
      return matchSearch && matchStatus;
    }).toList();
  }

  // --- Statistiques pour les chips ---
  int get activeCount => _trips.where((t) => t.status == 'ACTIVE').length;
  int get plannedCount => _trips.where((t) => t.status == 'PLANNED').length;
  int get completedCount => _trips.where((t) => t.status == 'COMPLETED').length;
  int get totalStudents => _trips.fold(0, (sum, t) => sum + t.totalStudents);

  // --- Filtres ---
  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void setStatusFilter(String status) {
    _statusFilter = status;
    notifyListeners();
  }

  /// Charge la liste des voyages depuis l'API.
  Future<void> loadTrips() async {
    _listState = TripLoadState.loading;
    _listError = null;
    notifyListeners();

    try {
      final data = await _apiClient.getTrips();
      _trips = data.map((e) => Trip.fromJson(e as Map<String, dynamic>)).toList();
      // Tri par date décroissante
      _trips.sort((a, b) => b.date.compareTo(a.date));
      _listState = TripLoadState.success;
    } on ApiException catch (e) {
      _listError = e.message;
      _listState = TripLoadState.error;
    } catch (e) {
      _listError = 'Erreur inattendue : $e';
      _listState = TripLoadState.error;
    }

    notifyListeners();
  }

  /// Charge la liste des classes disponibles (pour le formulaire création).
  Future<void> loadClasses() async {
    try {
      final data = await _apiClient.getClasses();
      _classes = data.map((e) => SchoolClass.fromJson(e as Map<String, dynamic>)).toList();
      notifyListeners();
    } catch (_) {
      // Erreur silencieuse — l'UI affichera un message si la liste est vide
    }
  }

  /// Crée un nouveau voyage puis recharge la liste.
  Future<bool> createTrip({
    required String destination,
    required String date,
    required List<String> classIds,
    String? description,
  }) async {
    _opState = TripLoadState.loading;
    _opError = null;
    notifyListeners();

    try {
      await _apiClient.createTrip(
        destination: destination,
        date: date,
        classIds: classIds,
        description: description,
      );
      _opState = TripLoadState.success;
      notifyListeners();
      await loadTrips();
      return true;
    } on ApiException catch (e) {
      _opError = e.message;
      _opState = TripLoadState.error;
      notifyListeners();
      return false;
    }
  }

  /// Met à jour un voyage existant puis recharge la liste.
  Future<bool> updateTrip(
    String tripId, {
    String? destination,
    String? date,
    String? description,
    String? status,
    List<String>? classIds,
  }) async {
    _opState = TripLoadState.loading;
    _opError = null;
    notifyListeners();

    try {
      await _apiClient.updateTrip(
        tripId,
        destination: destination,
        date: date,
        description: description,
        status: status,
        classIds: classIds,
      );
      _opState = TripLoadState.success;
      notifyListeners();
      await loadTrips();
      return true;
    } on ApiException catch (e) {
      _opError = e.message;
      _opState = TripLoadState.error;
      notifyListeners();
      return false;
    }
  }

  /// Supprime un voyage puis recharge la liste.
  Future<bool> deleteTrip(String tripId) async {
    _opState = TripLoadState.loading;
    _opError = null;
    notifyListeners();

    try {
      await _apiClient.deleteTrip(tripId);
      _opState = TripLoadState.success;
      notifyListeners();
      await loadTrips();
      return true;
    } on ApiException catch (e) {
      _opError = e.message;
      _opState = TripLoadState.error;
      notifyListeners();
      return false;
    }
  }

  /// Réinitialise l'état d'opération (après fermeture d'une dialog).
  void resetOpState() {
    _opState = TripLoadState.idle;
    _opError = null;
    notifyListeners();
  }
}
