import 'package:flutter/material.dart';
import '../../../core/api/api_client.dart';

/// Modèle local pour afficher un élève dans la liste.
class _StudentItem {
  final String id;
  final String lastName;
  final String firstName;
  final String? email;

  const _StudentItem({
    required this.id,
    required this.lastName,
    required this.firstName,
    this.email,
  });

  String get displayName => '$lastName $firstName';

  factory _StudentItem.fromJson(Map<String, dynamic> j) => _StudentItem(
        id: j['id'] as String,
        lastName: j['last_name'] as String,
        firstName: j['first_name'] as String,
        email: j['email'] as String?,
      );
}

/// Écran de listage des élèves (US 1.3 — vue élèves).
/// Affiche tous les élèves avec recherche, ajout, modification et suppression.
class StudentListScreen extends StatefulWidget {
  const StudentListScreen({super.key});

  @override
  State<StudentListScreen> createState() => _StudentListScreenState();
}

class _StudentListScreenState extends State<StudentListScreen> {
  final ApiClient _api = ApiClient();
  List<_StudentItem> _students = [];
  bool _loading = true;
  String? _error;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _api.getStudents();
      setState(() {
        _students = data.map(_StudentItem.fromJson).toList();
        _loading = false;
      });
    } on ApiException catch (e) {
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Erreur inattendue : $e';
        _loading = false;
      });
    }
  }

  List<_StudentItem> get _filtered {
    if (_search.isEmpty) return _students;
    final q = _search.toLowerCase();
    return _students.where((s) => s.displayName.toLowerCase().contains(q)).toList();
  }

  // ── Dialogs ───────────────────────────────────────────────────────────────

  /// Ouvre le dialog de création ou de modification d'un élève.
  /// [student] est null pour une création, non-null pour une modification.
  Future<void> _showStudentDialog([_StudentItem? student]) async {
    final firstNameCtrl = TextEditingController(text: student?.firstName ?? '');
    final lastNameCtrl = TextEditingController(text: student?.lastName ?? '');
    final emailCtrl = TextEditingController(text: student?.email ?? '');
    final formKey = GlobalKey<FormState>();
    bool saving = false;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(student == null ? 'Ajouter un élève' : 'Modifier l\'élève'),
          content: SizedBox(
            width: 400,
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: lastNameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Nom *',
                      border: OutlineInputBorder(),
                    ),
                    textCapitalization: TextCapitalization.words,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Le nom est obligatoire.' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: firstNameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Prénom *',
                      border: OutlineInputBorder(),
                    ),
                    textCapitalization: TextCapitalization.words,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Le prénom est obligatoire.' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: emailCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Email (optionnel)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.emailAddress,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.of(ctx).pop(false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      setLocal(() => saving = true);
                      try {
                        final email = emailCtrl.text.trim().isEmpty
                            ? null
                            : emailCtrl.text.trim();
                        if (student == null) {
                          await _api.createStudent(
                            firstName: firstNameCtrl.text.trim(),
                            lastName: lastNameCtrl.text.trim(),
                            email: email,
                          );
                        } else {
                          await _api.updateStudent(
                            student.id,
                            firstName: firstNameCtrl.text.trim(),
                            lastName: lastNameCtrl.text.trim(),
                            email: email,
                          );
                        }
                        if (ctx.mounted) Navigator.of(ctx).pop(true);
                      } on ApiException catch (e) {
                        setLocal(() => saving = false);
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(
                              content: Text('Erreur : ${e.message}'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
              child: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(student == null ? 'Ajouter' : 'Enregistrer'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && mounted) {
      _load();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(student == null ? 'Élève ajouté.' : 'Élève mis à jour.'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  /// Affiche un dialog de confirmation avant suppression.
  Future<void> _deleteStudent(_StudentItem student) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer l\'élève ?'),
        content: Text(
          'Voulez-vous supprimer définitivement ${student.displayName} ?\n\n'
          'Cette action est irréversible.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await _api.deleteStudent(student.id);
        _load();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Élève supprimé.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } on ApiException catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erreur : ${e.message}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // En-tête
        Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            children: [
              Text(
                'Élèves',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(width: 16),
              if (!_loading)
                Chip(
                  label: Text('${_students.length} au total'),
                  padding: EdgeInsets.zero,
                ),
              const Spacer(),
              IconButton(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                tooltip: 'Actualiser',
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: () => _showStudentDialog(),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Ajouter'),
              ),
            ],
          ),
        ),

        // Barre de recherche
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Rechercher par nom ou prénom…',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Liste
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? _ErrorView(message: _error!, onRetry: _load)
                  : _students.isEmpty
                      ? _EmptyView(onAdd: () => _showStudentDialog())
                      : _StudentList(
                          students: _filtered,
                          onEdit: _showStudentDialog,
                          onDelete: _deleteStudent,
                        ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Liste des élèves
// ---------------------------------------------------------------------------

class _StudentList extends StatelessWidget {
  final List<_StudentItem> students;
  final void Function(_StudentItem) onEdit;
  final void Function(_StudentItem) onDelete;

  const _StudentList({
    required this.students,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    if (students.isEmpty) {
      return const Center(child: Text('Aucun résultat pour cette recherche.'));
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      itemCount: students.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (ctx, i) {
        final s = students[i];
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: Theme.of(ctx).colorScheme.primaryContainer,
            child: Text(
              s.lastName.isNotEmpty ? s.lastName[0].toUpperCase() : '?',
              style: TextStyle(
                color: Theme.of(ctx).colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          title: Text(s.displayName),
          subtitle: s.email != null ? Text(s.email!) : null,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 20),
                tooltip: 'Modifier',
                onPressed: () => onEdit(s),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                tooltip: 'Supprimer',
                onPressed: () => onDelete(s),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Vues utilitaires
// ---------------------------------------------------------------------------

class _EmptyView extends StatelessWidget {
  final VoidCallback onAdd;

  const _EmptyView({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.people_outline, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            'Aucun élève enregistré',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          const Text('Importez des élèves via le menu "Import élèves" ou ajoutez-en manuellement.'),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text('Ajouter un élève'),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.red),
          const SizedBox(height: 12),
          Text(message),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Réessayer'),
          ),
        ],
      ),
    );
  }
}
