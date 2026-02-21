import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/class_provider.dart';

/// Dialog de création ou de modification d'une classe scolaire.
class ClassFormDialog extends StatefulWidget {
  /// Si null → création, sinon → modification.
  final SchoolClassModel? existing;

  const ClassFormDialog({super.key, this.existing});

  @override
  State<ClassFormDialog> createState() => _ClassFormDialogState();
}

class _ClassFormDialogState extends State<ClassFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _yearCtrl;
  bool _loading = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.existing?.name ?? '');
    _yearCtrl = TextEditingController(text: widget.existing?.year ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _yearCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    final provider = context.read<ClassProvider>();
    final name = _nameCtrl.text.trim();
    final year = _yearCtrl.text.trim();

    String? err;
    if (_isEdit) {
      err = await provider.updateClass(
        widget.existing!.id,
        name,
        year: year.isEmpty ? null : year,
      );
    } else {
      err = await provider.createClass(name, year: year.isEmpty ? null : year);
    }

    if (!mounted) return;
    if (err != null) {
      setState(() {
        _loading = false;
        _error = err;
      });
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEdit ? 'Modifier la classe' : 'Nouvelle classe'),
      content: SizedBox(
        width: 360,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    _error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nom de la classe *',
                  hintText: 'ex. 3A, Terminale S…',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Le nom est obligatoire' : null,
                autofocus: true,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _yearCtrl,
                decoration: const InputDecoration(
                  labelText: 'Année scolaire (optionnel)',
                  hintText: 'ex. 2025-2026',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _loading ? null : _submit,
          child: _loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Text(_isEdit ? 'Enregistrer' : 'Créer'),
        ),
      ],
    );
  }
}
