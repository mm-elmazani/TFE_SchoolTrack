import 'package:flutter/material.dart';
import '../../../core/api/api_client.dart';

/// État de l'écran Classes.
enum ClassState { idle, loading, success, error }

/// Modèle local pour une classe scolaire.
class SchoolClassModel {
  final String id;
  final String name;
  final String? year;
  final int nbStudents;
  final int nbTeachers;

  const SchoolClassModel({
    required this.id,
    required this.name,
    this.year,
    required this.nbStudents,
    required this.nbTeachers,
  });

  factory SchoolClassModel.fromJson(Map<String, dynamic> json) {
    return SchoolClassModel(
      id: json['id'] as String,
      name: json['name'] as String,
      year: json['year'] as String?,
      nbStudents: (json['nb_students'] as int?) ?? 0,
      nbTeachers: (json['nb_teachers'] as int?) ?? 0,
    );
  }
}

/// Provider gérant la liste des classes et les opérations CRUD.
class ClassProvider extends ChangeNotifier {
  final ApiClient _api;

  ClassState _state = ClassState.idle;
  List<SchoolClassModel> _classes = [];
  String? _errorMessage;

  ClassProvider({ApiClient? api}) : _api = api ?? ApiClient();

  ClassState get state => _state;
  List<SchoolClassModel> get classes => _classes;
  String? get errorMessage => _errorMessage;

  // ---------------------------------------------------------------------------
  // Chargement
  // ---------------------------------------------------------------------------

  Future<void> loadClasses() async {
    _state = ClassState.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      final data = await _api.getClasses();
      _classes = data.map(SchoolClassModel.fromJson).toList();
      _state = ClassState.success;
    } on ApiException catch (e) {
      _state = ClassState.error;
      _errorMessage = e.message;
    } catch (e) {
      _state = ClassState.error;
      _errorMessage = 'Erreur inattendue : $e';
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // CRUD
  // ---------------------------------------------------------------------------

  Future<String?> createClass(String name, {String? year}) async {
    try {
      final json = await _api.createClass(name, year: year);
      _classes.add(SchoolClassModel.fromJson(json));
      notifyListeners();
      return null; // succès
    } on ApiException catch (e) {
      return e.message;
    } catch (e) {
      return 'Erreur inattendue : $e';
    }
  }

  Future<String?> updateClass(String classId, String name, {String? year}) async {
    try {
      final json = await _api.updateClass(classId, name: name, year: year);
      final updated = SchoolClassModel.fromJson(json);
      final idx = _classes.indexWhere((c) => c.id == classId);
      if (idx >= 0) _classes[idx] = updated;
      notifyListeners();
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (e) {
      return 'Erreur inattendue : $e';
    }
  }

  Future<String?> deleteClass(String classId) async {
    try {
      await _api.deleteClass(classId);
      _classes.removeWhere((c) => c.id == classId);
      notifyListeners();
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (e) {
      return 'Erreur inattendue : $e';
    }
  }

  /// Assigne une liste d'élèves à une classe et recharge la liste.
  Future<String?> assignStudents(String classId, List<String> studentIds) async {
    try {
      final json = await _api.assignStudents(classId, studentIds);
      final updated = SchoolClassModel.fromJson(json);
      final idx = _classes.indexWhere((c) => c.id == classId);
      if (idx >= 0) _classes[idx] = updated;
      notifyListeners();
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (e) {
      return 'Erreur inattendue : $e';
    }
  }

  /// Retire un élève d'une classe.
  /// Le rechargement du compteur est délégué à [loadClasses] après toutes les opérations.
  Future<String?> removeStudent(String classId, String studentId) async {
    try {
      await _api.removeStudentFromClass(classId, studentId);
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (e) {
      return 'Erreur inattendue : $e';
    }
  }
}
