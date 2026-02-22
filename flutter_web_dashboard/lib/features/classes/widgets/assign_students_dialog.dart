import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/api/api_client.dart';
import '../providers/class_provider.dart';

/// Modèle local pour un élève dans la liste de sélection.
class _StudentItem {
  final String id;
  final String lastName;
  final String firstName;
  bool selected;

  _StudentItem({
    required this.id,
    required this.lastName,
    required this.firstName,
  }) : selected = false;

  String get displayName => '$lastName $firstName';
}

/// Dialog permettant d'ajouter ou retirer des élèves d'une classe.
/// - Cases pré-cochées = élèves déjà dans la classe
/// - Cocher une case non cochée → ajout
/// - Décocher une case cochée → retrait
class AssignStudentsDialog extends StatefulWidget {
  final String classId;
  final String className;

  const AssignStudentsDialog({
    super.key,
    required this.classId,
    required this.className,
  });

  @override
  State<AssignStudentsDialog> createState() => _AssignStudentsDialogState();
}

class _AssignStudentsDialogState extends State<AssignStudentsDialog> {
  final ApiClient _api = ApiClient();
  List<_StudentItem> _students = [];
  Set<String> _initiallyAssigned = {}; // IDs des élèves déjà dans la classe
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _loadStudents();
  }

  Future<void> _loadStudents() async {
    try {
      // Chargement en parallèle : tous les élèves + ceux déjà dans la classe
      final results = await Future.wait([
        _api.getStudents(),
        _api.getClassStudentIds(widget.classId),
      ]);

      final allStudents = results[0] as List<Map<String, dynamic>>;
      final assignedIds = Set<String>.from(results[1] as List<String>);

      setState(() {
        _initiallyAssigned = assignedIds;
        _students = allStudents.map((s) {
          final item = _StudentItem(
            id: s['id'] as String,
            lastName: s['last_name'] as String,
            firstName: s['first_name'] as String,
          );
          item.selected = assignedIds.contains(item.id);
          return item;
        }).toList();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Impossible de charger les élèves.';
        _loading = false;
      });
    }
  }

  List<_StudentItem> get _filtered {
    if (_search.isEmpty) return _students;
    final q = _search.toLowerCase();
    return _students.where((s) => s.displayName.toLowerCase().contains(q)).toList();
  }

  /// Calcule le diff entre l'état initial et l'état courant.
  List<String> get _toAdd => _students
      .where((s) => s.selected && !_initiallyAssigned.contains(s.id))
      .map((s) => s.id)
      .toList();

  List<String> get _toRemove => _students
      .where((s) => !s.selected && _initiallyAssigned.contains(s.id))
      .map((s) => s.id)
      .toList();

  Future<void> _save() async {
    final toAdd = _toAdd;
    final toRemove = _toRemove;

    // Aucun changement → fermer sans appel API
    if (toAdd.isEmpty && toRemove.isEmpty) {
      Navigator.of(context).pop();
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final provider = context.read<ClassProvider>();

    // Ajouts
    if (toAdd.isNotEmpty) {
      final err = await provider.assignStudents(widget.classId, toAdd);
      if (err != null && mounted) {
        setState(() {
          _saving = false;
          _error = err;
        });
        return;
      }
    }

    // Retraits
    for (final studentId in toRemove) {
      final err = await provider.removeStudent(widget.classId, studentId);
      if (err != null && mounted) {
        setState(() {
          _saving = false;
          _error = err;
        });
        return;
      }
    }

    // Rechargement complet pour avoir les bons compteurs sur les cartes
    await provider.loadClasses();

    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final addCount = _toAdd.length;
    final removeCount = _toRemove.length;
    final hasChanges = addCount > 0 || removeCount > 0;

    return AlertDialog(
      title: Text('Élèves — ${widget.className}'),
      content: SizedBox(
        width: 480,
        height: 480,
        child: Column(
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            // Barre de recherche
            TextField(
              decoration: const InputDecoration(
                hintText: 'Rechercher un élève…',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
            const SizedBox(height: 8),
            // Liste des élèves
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _students.isEmpty
                      ? const Center(
                          child: Text('Aucun élève dans la base de données.'),
                        )
                      : ListView.builder(
                          itemCount: _filtered.length,
                          itemBuilder: (ctx, i) {
                            final student = _filtered[i];
                            return CheckboxListTile(
                              title: Text(student.displayName),
                              value: student.selected,
                              onChanged: (v) =>
                                  setState(() => student.selected = v ?? false),
                              dense: true,
                            );
                          },
                        ),
            ),
            // Résumé des changements
            if (!_loading)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: _buildChangeSummary(addCount, removeCount),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Text(hasChanges ? 'Enregistrer' : 'Fermer'),
        ),
      ],
    );
  }

  Widget _buildChangeSummary(int addCount, int removeCount) {
    if (addCount == 0 && removeCount == 0) {
      return Text(
        '${_students.where((s) => s.selected).length} élève(s) dans la classe',
        style: const TextStyle(color: Colors.grey),
      );
    }
    final parts = <String>[];
    if (addCount > 0) parts.add('+$addCount à ajouter');
    if (removeCount > 0) parts.add('-$removeCount à retirer');
    return Text(
      parts.join('  •  '),
      style: TextStyle(
        fontWeight: FontWeight.w500,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }
}
