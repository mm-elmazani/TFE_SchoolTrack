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

/// Dialog permettant de sélectionner des élèves à assigner à une classe.
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
        _students = allStudents.map((s) {
          final item = _StudentItem(
            id: s['id'] as String,
            lastName: s['last_name'] as String,
            firstName: s['first_name'] as String,
          );
          // Pré-cocher si l'élève est déjà dans la classe
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
    return _students
        .where((s) => s.displayName.toLowerCase().contains(q))
        .toList();
  }

  Future<void> _assign() async {
    final selected = _students.where((s) => s.selected).map((s) => s.id).toList();
    if (selected.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _saving = true);
    final provider = context.read<ClassProvider>();
    final err = await provider.assignStudents(widget.classId, selected);
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _saving = false;
        _error = err;
      });
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedCount = _students.where((s) => s.selected).length;

    return AlertDialog(
      title: Text('Assigner des élèves — ${widget.className}'),
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
            if (selectedCount > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '$selectedCount élève(s) sélectionné(s)',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
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
          onPressed: _saving ? null : _assign,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Text(selectedCount == 0 ? 'Fermer' : 'Assigner ($selectedCount)'),
        ),
      ],
    );
  }
}
