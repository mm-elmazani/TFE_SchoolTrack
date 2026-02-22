import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/class_provider.dart';
import '../widgets/assign_students_dialog.dart';
import '../widgets/class_form_dialog.dart';

/// Écran de gestion des classes scolaires (US 1.3).
/// Permet de lister, créer, modifier, supprimer des classes
/// et d'assigner des élèves à chacune.
class ClassListScreen extends StatelessWidget {
  const ClassListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ClassProvider()..loadClasses(),
      child: const _ClassListBody(),
    );
  }
}

class _ClassListBody extends StatelessWidget {
  const _ClassListBody();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ClassProvider>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Barre d'actions
        Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            children: [
              Text(
                'Classes scolaires',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: () => _showCreateDialog(context),
                icon: const Icon(Icons.add),
                label: const Text('Nouvelle classe'),
              ),
            ],
          ),
        ),
        // Contenu
        Expanded(
          child: switch (provider.state) {
            ClassState.loading => const Center(child: CircularProgressIndicator()),
            ClassState.error => _ErrorView(
                message: provider.errorMessage ?? 'Erreur inconnue',
                onRetry: () => context.read<ClassProvider>().loadClasses(),
              ),
            _ => provider.classes.isEmpty
                ? _EmptyView(onAdd: () => _showCreateDialog(context))
                : _ClassGrid(classes: provider.classes),
          },
        ),
      ],
    );
  }

  void _showCreateDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => ChangeNotifierProvider.value(
        value: context.read<ClassProvider>(),
        child: const ClassFormDialog(),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Grille de classes
// ---------------------------------------------------------------------------

class _ClassGrid extends StatelessWidget {
  final List<SchoolClassModel> classes;

  const _ClassGrid({required this.classes});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 320,
          childAspectRatio: 1.6,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
        ),
        itemCount: classes.length,
        itemBuilder: (ctx, i) => _ClassCard(schoolClass: classes[i]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Carte d'une classe
// ---------------------------------------------------------------------------

class _ClassCard extends StatelessWidget {
  final SchoolClassModel schoolClass;

  const _ClassCard({required this.schoolClass});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Nom + menu
            Row(
              children: [
                Expanded(
                  child: Text(
                    schoolClass.name,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _CardMenu(schoolClass: schoolClass),
              ],
            ),
            if (schoolClass.year != null) ...[
              const SizedBox(height: 2),
              Text(
                schoolClass.year!,
                style: TextStyle(color: colorScheme.outline, fontSize: 12),
              ),
            ],
            const Spacer(),
            // Compteurs
            Row(
              children: [
                Icon(Icons.people_outline, size: 16, color: colorScheme.primary),
                const SizedBox(width: 4),
                Text('${schoolClass.nbStudents} élève(s)'),
                const SizedBox(width: 16),
                Icon(Icons.school_outlined, size: 16, color: colorScheme.secondary),
                const SizedBox(width: 4),
                Text('${schoolClass.nbTeachers} enseignant(s)'),
              ],
            ),
            const SizedBox(height: 8),
            // Bouton assigner élèves
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _showAssignDialog(context),
                icon: const Icon(Icons.person_add_outlined, size: 16),
                label: const Text('Assigner des élèves'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAssignDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => ChangeNotifierProvider.value(
        value: context.read<ClassProvider>(),
        child: AssignStudentsDialog(
          classId: schoolClass.id,
          className: schoolClass.name,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Menu contextuel (modifier / supprimer)
// ---------------------------------------------------------------------------

class _CardMenu extends StatelessWidget {
  final SchoolClassModel schoolClass;

  const _CardMenu({required this.schoolClass});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      onSelected: (action) => _onAction(context, action),
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: 'edit',
          child: ListTile(
            leading: Icon(Icons.edit_outlined),
            title: Text('Modifier'),
            dense: true,
          ),
        ),
        const PopupMenuItem(
          value: 'delete',
          child: ListTile(
            leading: Icon(Icons.delete_outline, color: Colors.red),
            title: Text('Supprimer', style: TextStyle(color: Colors.red)),
            dense: true,
          ),
        ),
      ],
    );
  }

  void _onAction(BuildContext context, String action) {
    switch (action) {
      case 'edit':
        showDialog<void>(
          context: context,
          builder: (_) => ChangeNotifierProvider.value(
            value: context.read<ClassProvider>(),
            child: ClassFormDialog(existing: schoolClass),
          ),
        );
      case 'delete':
        _confirmDelete(context);
    }
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final provider = context.read<ClassProvider>();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer la classe'),
        content: Text(
          'Supprimer "${schoolClass.name}" ? Cette action est irréversible.',
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

    if (confirm == true && context.mounted) {
      final err = await provider.deleteClass(schoolClass.id);
      if (err != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(err),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
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
          Icon(Icons.class_outlined, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            'Aucune classe enregistrée',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text('Créer la première classe'),
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
