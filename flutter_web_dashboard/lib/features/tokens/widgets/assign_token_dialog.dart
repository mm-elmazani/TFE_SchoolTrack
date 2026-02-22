import 'package:flutter/material.dart';
import '../../../core/api/api_client.dart';
import '../providers/token_provider.dart';

/// Dialogue d'assignation ou de réassignation d'un bracelet à un élève (US 1.5).
///
/// En mode réassignation, une justification est obligatoire.
class AssignTokenDialog extends StatefulWidget {
  /// Élève concerné par l'opération.
  final TripStudentInfo student;

  /// Vrai si l'élève a déjà un bracelet (mode réassignation).
  final bool isReassign;

  /// Provider pour déclencher l'action sur l'API.
  final TokenProvider provider;

  const AssignTokenDialog({
    super.key,
    required this.student,
    required this.isReassign,
    required this.provider,
  });

  @override
  State<AssignTokenDialog> createState() => _AssignTokenDialogState();
}

class _AssignTokenDialogState extends State<AssignTokenDialog> {
  final _formKey = GlobalKey<FormState>();
  final _tokenUidController = TextEditingController();
  final _justificationController = TextEditingController();

  String _assignmentType = 'NFC_PHYSICAL';
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _tokenUidController.dispose();
    _justificationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title =
        widget.isReassign ? 'Réassigner un bracelet' : 'Assigner un bracelet';

    return AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Résumé de l'élève concerné
              _StudentInfoTile(student: widget.student),
              const SizedBox(height: 16),

              // Token actuel (mode réassignation uniquement)
              if (widget.isReassign && widget.student.tokenUid != null) ...[
                Text(
                  'Token actuel : ${widget.student.tokenUid}  '
                  '(${_typeLabel(widget.student.assignmentType)})',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                ),
                const SizedBox(height: 12),
              ],

              // Champ UID du (nouveau) bracelet
              TextFormField(
                controller: _tokenUidController,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText:
                      widget.isReassign ? 'Nouveau token UID' : 'Token UID',
                  hintText: 'Ex : AABBCCDD',
                  border: const OutlineInputBorder(),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return "L'UID du bracelet est obligatoire";
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),

              // Type d'assignation
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Type de bracelet',
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _assignmentType,
                    isDense: true,
                    isExpanded: true,
                    items: const [
                      DropdownMenuItem(
                          value: 'NFC_PHYSICAL', child: Text('NFC Physique')),
                      DropdownMenuItem(
                          value: 'QR_PHYSICAL', child: Text('QR Physique')),
                      DropdownMenuItem(
                          value: 'QR_DIGITAL', child: Text('QR Digital')),
                    ],
                    onChanged: (v) => setState(() => _assignmentType = v!),
                  ),
                ),
              ),

              // Justification (réassignation uniquement)
              if (widget.isReassign) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _justificationController,
                  decoration: const InputDecoration(
                    labelText: 'Justification (obligatoire)',
                    hintText: 'Ex : Bracelet endommagé',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'La justification est obligatoire';
                    }
                    return null;
                  },
                ),
              ],

              // Message d'erreur API
              if (_error != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline,
                          size: 16, color: Colors.red.shade700),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _error!,
                          style: TextStyle(
                              color: Colors.red.shade800, fontSize: 13),
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
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _isLoading ? null : _submit,
          child: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : Text(widget.isReassign ? 'Réassigner' : 'Assigner'),
        ),
      ],
    );
  }

  /// Valide le formulaire et envoie la requête d'assignation à l'API.
  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final uid = _tokenUidController.text.trim().toUpperCase();
      if (widget.isReassign) {
        await widget.provider.reassignToken(
          studentId: widget.student.id,
          tokenUid: uid,
          assignmentType: _assignmentType,
          justification: _justificationController.text.trim(),
        );
      } else {
        await widget.provider.assignToken(
          studentId: widget.student.id,
          tokenUid: uid,
          assignmentType: _assignmentType,
        );
      }
      if (mounted) Navigator.pop(context);
    } on ApiException catch (e) {
      setState(() {
        _error = e.message;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Erreur inattendue : $e';
        _isLoading = false;
      });
    }
  }

  /// Libellé lisible d'un type d'assignation.
  String _typeLabel(String? type) {
    switch (type) {
      case 'NFC_PHYSICAL':
        return 'NFC Physique';
      case 'QR_PHYSICAL':
        return 'QR Physique';
      case 'QR_DIGITAL':
        return 'QR Digital';
      default:
        return type ?? '';
    }
  }
}

/// Tuile affichant l'identité de l'élève dans le dialogue.
class _StudentInfoTile extends StatelessWidget {
  final TripStudentInfo student;

  const _StudentInfoTile({required this.student});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.person_outline, size: 18),
          const SizedBox(width: 8),
          Text(
            '${student.lastName} ${student.firstName}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          if (student.email != null) ...[
            const SizedBox(width: 8),
            Text(
              student.email!,
              style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}
