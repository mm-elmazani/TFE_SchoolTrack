import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/trip_provider.dart';

/// Dialog de création ou modification d'un voyage.
/// Champs : destination, date, classes (multi-sélection), description, statut (édition uniquement).
class TripFormDialog extends StatefulWidget {
  /// Si non null, le dialog est en mode édition
  final Trip? trip;

  const TripFormDialog({super.key, this.trip});

  /// Ouvre la dialog et retourne true si une opération a réussi.
  /// Transmet le TripProvider existant via ChangeNotifierProvider.value
  /// car showDialog crée un nouveau contexte sans accès au provider parent.
  static Future<bool> show(BuildContext context, {Trip? trip}) async {
    final provider = context.read<TripProvider>();
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) => ChangeNotifierProvider.value(
            value: provider,
            child: TripFormDialog(trip: trip),
          ),
        ) ??
        false;
  }

  @override
  State<TripFormDialog> createState() => _TripFormDialogState();
}

class _TripFormDialogState extends State<TripFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _destinationCtrl;
  late final TextEditingController _descriptionCtrl;

  DateTime? _selectedDate;
  String _selectedStatus = 'PLANNED';
  final Set<String> _selectedClassIds = {};

  bool get _isEdit => widget.trip != null;

  static const _statusOptions = [
    ('PLANNED', 'À venir'),
    ('ACTIVE', 'En cours'),
    ('COMPLETED', 'Terminé'),
    ('ARCHIVED', 'Archivé'),
  ];

  @override
  void initState() {
    super.initState();
    final trip = widget.trip;
    _destinationCtrl = TextEditingController(text: trip?.destination ?? '');
    _descriptionCtrl = TextEditingController(text: trip?.description ?? '');
    _selectedDate = trip?.date;
    _selectedStatus = trip?.status ?? 'PLANNED';

    // Charge les classes disponibles au premier affichage
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<TripProvider>().loadClasses();
    });
  }

  @override
  void dispose() {
    _destinationCtrl.dispose();
    _descriptionCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? now.add(const Duration(days: 1)),
      firstDate: now.add(const Duration(days: 1)),
      lastDate: DateTime(now.year + 3),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Veuillez sélectionner une date.')),
      );
      return;
    }
    if (!_isEdit && _selectedClassIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Veuillez sélectionner au moins une classe.')),
      );
      return;
    }

    final provider = context.read<TripProvider>();
    final dateStr =
        '${_selectedDate!.year}-${_selectedDate!.month.toString().padLeft(2, '0')}-${_selectedDate!.day.toString().padLeft(2, '0')}';

    bool success;
    if (_isEdit) {
      success = await provider.updateTrip(
        widget.trip!.id,
        destination: _destinationCtrl.text.trim(),
        date: dateStr,
        description: _descriptionCtrl.text.trim().isEmpty ? null : _descriptionCtrl.text.trim(),
        status: _selectedStatus,
        classIds: _selectedClassIds.isNotEmpty ? _selectedClassIds.toList() : null,
      );
    } else {
      success = await provider.createTrip(
        destination: _destinationCtrl.text.trim(),
        date: dateStr,
        classIds: _selectedClassIds.toList(),
        description: _descriptionCtrl.text.trim().isEmpty ? null : _descriptionCtrl.text.trim(),
      );
    }

    if (mounted) {
      if (success) {
        Navigator.of(context).pop(true);
      }
      // En cas d'erreur, le message est affiché dans le dialog via opError
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TripProvider>();
    final isLoading = provider.opState == TripLoadState.loading;
    final classes = provider.classes;

    return AlertDialog(
      title: Text(_isEdit ? 'Modifier le voyage' : 'Nouveau voyage'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Destination
                TextFormField(
                  controller: _destinationCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Destination *',
                    hintText: 'Ex: Musée du Louvre, Paris',
                    prefixIcon: Icon(Icons.location_on_outlined),
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'La destination est obligatoire.' : null,
                ),
                const SizedBox(height: 16),

                // Date
                InkWell(
                  onTap: _pickDate,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Date du voyage *',
                      prefixIcon: Icon(Icons.calendar_today_outlined),
                      border: OutlineInputBorder(),
                    ),
                    child: Text(
                      _selectedDate != null
                          ? '${_selectedDate!.day.toString().padLeft(2, '0')}/${_selectedDate!.month.toString().padLeft(2, '0')}/${_selectedDate!.year}'
                          : 'Sélectionner une date',
                      style: TextStyle(
                        color: _selectedDate != null
                            ? Colors.black87
                            : Colors.grey.shade500,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Sélection classes (création : obligatoire / édition : optionnelle)
                Text(
                  _isEdit ? 'Modifier les classes (optionnel)' : 'Classes *',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                ),
                if (_isEdit)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      'Laisser vide pour ne pas modifier les élèves du voyage.',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                    ),
                  ),
                const SizedBox(height: 8),
                classes.isEmpty
                    ? Text(
                        'Aucune classe disponible. Importez d\'abord des élèves avec leur classe.',
                        style: TextStyle(color: Colors.orange.shade700, fontSize: 13),
                      )
                    : Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: classes.map((c) {
                          final selected = _selectedClassIds.contains(c.id);
                          return FilterChip(
                            label: Text(c.displayName),
                            selected: selected,
                            onSelected: (val) {
                              setState(() {
                                if (val) {
                                  _selectedClassIds.add(c.id);
                                } else {
                                  _selectedClassIds.remove(c.id);
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                const SizedBox(height: 16),

                // Statut (édition uniquement)
                if (_isEdit) ...[
                  DropdownButtonFormField<String>(
                    initialValue: _selectedStatus,
                    decoration: const InputDecoration(
                      labelText: 'Statut',
                      prefixIcon: Icon(Icons.flag_outlined),
                      border: OutlineInputBorder(),
                    ),
                    items: _statusOptions
                        .map((s) => DropdownMenuItem(value: s.$1, child: Text(s.$2)))
                        .toList(),
                    onChanged: (v) => setState(() => _selectedStatus = v!),
                  ),
                  const SizedBox(height: 16),
                ],

                // Description (optionnelle)
                TextFormField(
                  controller: _descriptionCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Description (optionnelle)',
                    hintText: 'Notes sur le voyage...',
                    prefixIcon: Icon(Icons.notes_outlined),
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),

                // Message d'erreur API
                if (provider.opState == TripLoadState.error && provider.opError != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline, color: Colors.red.shade700, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            provider.opError!,
                            style: TextStyle(color: Colors.red.shade800, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: isLoading ? null : () => Navigator.of(context).pop(false),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: isLoading ? null : _submit,
          child: isLoading
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
