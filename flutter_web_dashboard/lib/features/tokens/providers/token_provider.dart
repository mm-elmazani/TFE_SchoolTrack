import 'package:flutter/foundation.dart';
import '../../../core/api/api_client.dart';

// ----------------------------------------------------------------
// Modèles de données
// ----------------------------------------------------------------

/// Résumé d'une classe dans un voyage (nom + nb élèves inscrits).
class TripClassSummary {
  final String name;
  final int studentCount;

  const TripClassSummary({required this.name, required this.studentCount});

  factory TripClassSummary.fromJson(Map<String, dynamic> j) => TripClassSummary(
        name: j['name'] as String,
        studentCount: j['student_count'] as int,
      );
}

/// Résumé d'un voyage pour le sélecteur dropdown.
class TripSummary {
  final String id;
  final String destination;
  final String date;
  final String status;
  final int totalStudents;
  final List<TripClassSummary> classes;

  const TripSummary({
    required this.id,
    required this.destination,
    required this.date,
    required this.status,
    required this.totalStudents,
    this.classes = const [],
  });

  factory TripSummary.fromJson(Map<String, dynamic> j) => TripSummary(
        id: j['id'] as String,
        destination: j['destination'] as String,
        date: j['date'] as String,
        status: j['status'] as String,
        totalStudents: j['total_students'] as int? ?? 0,
        classes: (j['classes'] as List<dynamic>? ?? [])
            .map((c) => TripClassSummary.fromJson(c as Map<String, dynamic>))
            .toList(),
      );

  /// Libellé affiché dans le dropdown.
  /// Format : "Bruxelles — 3B (14) · 4A (26) — 2028-05-18"
  /// Si > 3 classes : affiche les 3 premières + "+N"
  String get label {
    if (classes.isEmpty) {
      return '$destination — $date';
    }
    final shown = classes.take(3);
    final overflow = classes.length > 3 ? '  +${classes.length - 3}' : '';
    final classStr =
        shown.map((c) => '${c.name} (${c.studentCount})').join(' · ') +
            overflow;
    return '$destination — $classStr — $date';
  }

  @override
  bool operator ==(Object other) => other is TripSummary && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Élève d'un voyage avec son statut d'assignation bracelet.
class TripStudentInfo {
  final String id;
  final String firstName;
  final String lastName;
  final String? email;
  final String? tokenUid;
  final String? assignmentType;
  final String? assignedAt;

  const TripStudentInfo({
    required this.id,
    required this.firstName,
    required this.lastName,
    this.email,
    this.tokenUid,
    this.assignmentType,
    this.assignedAt,
  });

  /// Vrai si l'élève a un bracelet actif sur ce voyage.
  bool get isAssigned => tokenUid != null;

  String get fullName => '$lastName $firstName';

  factory TripStudentInfo.fromJson(Map<String, dynamic> j) => TripStudentInfo(
        id: j['id'] as String,
        firstName: j['first_name'] as String,
        lastName: j['last_name'] as String,
        email: j['email'] as String?,
        tokenUid: j['token_uid'] as String?,
        assignmentType: j['assignment_type'] as String?,
        assignedAt: j['assigned_at'] as String?,
      );
}

/// Données complètes des élèves d'un voyage avec leur statut d'assignation.
class TripStudentsData {
  final String tripId;
  final int total;
  final int assigned;
  final int unassigned;
  final List<TripStudentInfo> students;

  const TripStudentsData({
    required this.tripId,
    required this.total,
    required this.assigned,
    required this.unassigned,
    required this.students,
  });

  factory TripStudentsData.fromJson(Map<String, dynamic> j) => TripStudentsData(
        tripId: j['trip_id'] as String,
        total: j['total'] as int,
        assigned: j['assigned'] as int,
        unassigned: j['unassigned'] as int,
        students: (j['students'] as List<dynamic>)
            .map((s) => TripStudentInfo.fromJson(s as Map<String, dynamic>))
            .toList(),
      );
}

// ----------------------------------------------------------------
// Provider
// ----------------------------------------------------------------

/// États de chargement de l'écran bracelets.
enum TokenLoadState { idle, loadingTrips, loadingStudents, ready, error }

/// Provider gérant l'état de l'écran d'assignation des bracelets (US 1.5).
class TokenProvider extends ChangeNotifier {
  final ApiClient _api;

  TokenProvider({ApiClient? api}) : _api = api ?? ApiClient();

  bool _disposed = false;

  TokenLoadState _state = TokenLoadState.idle;
  List<TripSummary> _trips = [];
  TripSummary? _selectedTrip;
  TripStudentsData? _studentsData;
  String? _errorMessage;
  bool _isReleasing = false;

  // --- Getters ---
  TokenLoadState get state => _state;
  List<TripSummary> get trips => _trips;
  TripSummary? get selectedTrip => _selectedTrip;
  TripStudentsData? get studentsData => _studentsData;
  String? get errorMessage => _errorMessage;
  bool get isReleasing => _isReleasing;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// Protège contre les appels après dispose (opérations async en cours).
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  /// URL d'export CSV pour le voyage sélectionné (null si aucun voyage sélectionné).
  String? get exportUrl =>
      _selectedTrip != null ? _api.getExportUrl(_selectedTrip!.id) : null;

  /// Charge la liste des voyages depuis l'API au démarrage de l'écran.
  Future<void> loadTrips() async {
    _state = TokenLoadState.loadingTrips;
    _errorMessage = null;
    notifyListeners();

    try {
      final list = await _api.getTrips();
      _trips = list.cast<Map<String, dynamic>>().map(TripSummary.fromJson).toList();
      _state = TokenLoadState.idle;
    } on ApiException catch (e) {
      _errorMessage = e.message;
      _state = TokenLoadState.error;
    } catch (e) {
      _errorMessage = 'Erreur inattendue : $e';
      _state = TokenLoadState.error;
    }

    notifyListeners();
  }

  /// Sélectionne un voyage et charge les élèves avec leur statut d'assignation.
  Future<void> selectTrip(TripSummary trip) async {
    _selectedTrip = trip;
    _state = TokenLoadState.loadingStudents;
    _studentsData = null;
    _errorMessage = null;
    notifyListeners();

    try {
      final json = await _api.getTripStudents(trip.id);
      _studentsData = TripStudentsData.fromJson(json);
      _state = TokenLoadState.ready;
    } on ApiException catch (e) {
      _errorMessage = e.message;
      _state = TokenLoadState.error;
    } catch (e) {
      _errorMessage = 'Erreur inattendue : $e';
      _state = TokenLoadState.error;
    }

    notifyListeners();
  }

  /// Rafraîchit les données du voyage actuellement sélectionné.
  Future<void> refresh() async {
    if (_selectedTrip != null) {
      await selectTrip(_selectedTrip!);
    }
  }

  /// Assigne un bracelet à un élève pour le voyage sélectionné.
  /// Lance une [ApiException] en cas de conflit ou d'erreur réseau.
  Future<void> assignToken({
    required String studentId,
    required String tokenUid,
    required String assignmentType,
  }) async {
    if (_selectedTrip == null) return;
    await _api.assignToken(
      tokenUid: tokenUid,
      studentId: studentId,
      tripId: _selectedTrip!.id,
      assignmentType: assignmentType,
    );
    await refresh();
  }

  /// Libère tous les bracelets actifs du voyage sélectionné.
  /// Retourne le nombre de bracelets libérés.
  /// Lance une [ApiException] en cas d'erreur réseau.
  Future<int> releaseTripTokens() async {
    if (_selectedTrip == null) return 0;
    _isReleasing = true;
    notifyListeners();
    try {
      final result = await _api.releaseTripTokens(_selectedTrip!.id);
      await refresh();
      return (result['released_count'] as int?) ?? 0;
    } finally {
      _isReleasing = false;
      notifyListeners();
    }
  }

  /// Réassigne un bracelet avec justification pour le voyage sélectionné.
  /// Lance une [ApiException] en cas de conflit ou d'erreur réseau.
  Future<void> reassignToken({
    required String studentId,
    required String tokenUid,
    required String assignmentType,
    required String justification,
  }) async {
    if (_selectedTrip == null) return;
    await _api.reassignToken(
      tokenUid: tokenUid,
      studentId: studentId,
      tripId: _selectedTrip!.id,
      assignmentType: assignmentType,
      justification: justification,
    );
    await refresh();
  }
}
