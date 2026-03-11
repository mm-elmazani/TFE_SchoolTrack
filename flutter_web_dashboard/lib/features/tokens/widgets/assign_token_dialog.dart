import 'package:flutter/material.dart';
import '../../../core/api/api_client.dart';
import '../providers/token_provider.dart';

/// Dialogue d'assignation ou de réassignation d'un bracelet à un élève (US 1.5).
///
/// En mode réassignation, une justification est obligatoire.
/// Charge la liste des tokens disponibles pour proposer un dropdown.
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
  final _justificationController = TextEditingController();

  String _assignmentType = 'NFC_PHYSICAL';
  bool _isLoading = false;
  String? _error;

  // Tokens disponibles depuis le stock
  List<Map<String, dynamic>> _availableTokens = [];
  bool _loadingTokens = true;
  String? _selectedTokenUid;
  bool _manualMode = false;
  final _manualUidController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadAvailableTokens();
  }

  Future<void> _loadAvailableTokens() async {
    try {
      final api = ApiClient();
      final tokens = await api.getTokens(status: 'AVAILABLE');
      if (mounted) {
        setState(() {
          _availableTokens = tokens;
          _loadingTokens = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadingTokens = false;
          _manualMode = true; // Fallback en mode manuel si erreur
        });
      }
    }
  }

  @override
  void dispose() {
    _justificationController.dispose();
    _manualUidController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title =
        widget.isReassign ? 'Réassigner un bracelet' : 'Assigner un bracelet';

    return AlertDialog(
      title: Text(title, style: const TextStyle(fontSize: 16)),
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
              const SizedBox(height: 14),

              // Token actuel (mode réassignation uniquement)
              if (widget.isReassign && widget.student.tokenUid != null) ...[
                Text(
                  'Token actuel : ${widget.student.tokenUid}  '
                  '(${_typeLabel(widget.student.assignmentType)})',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
                const SizedBox(height: 10),
              ],

              // Sélection du bracelet — dropdown ou saisie manuelle
              if (_loadingTokens)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 8),
                      Text('Chargement des bracelets...',
                          style: TextStyle(fontSize: 12)),
                    ],
                  ),
                )
              else if (!_manualMode && _availableTokens.isNotEmpty) ...[
                // Dropdown des tokens disponibles
                DropdownButtonFormField<String>(
                  value: _selectedTokenUid,
                  decoration: InputDecoration(
                    labelText: widget.isReassign
                        ? 'Nouveau bracelet'
                        : 'Bracelet disponible',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  isExpanded: true,
                  items: _availableTokens.map((t) {
                    final uid = t['token_uid'] as String;
                    final type = t['token_type'] as String;
                    final typeLabel =
                        type == 'NFC_PHYSICAL' ? 'NFC' : 'QR Phys.';
                    return DropdownMenuItem(
                      value: uid,
                      child: Text(
                        '$uid  ($typeLabel)',
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 13,
                        ),
                      ),
                    );
                  }).toList(),
                  onChanged: (v) {
                    setState(() {
                      _selectedTokenUid = v;
                      // Auto-selectionner le type selon le token choisi
                      if (v != null) {
                        final token = _availableTokens.firstWhere(
                          (t) => t['token_uid'] == v,
                        );
                        _assignmentType = token['token_type'] as String;
                      }
                    });
                  },
                  validator: (v) {
                    if (!_manualMode && (v == null || v.isEmpty)) {
                      return 'Selectionnez un bracelet';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 6),
                // Lien pour basculer en saisie manuelle
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => setState(() => _manualMode = true),
                    child: const Text(
                      'Saisir un UID manuellement',
                      style: TextStyle(fontSize: 11),
                    ),
                  ),
                ),
              ] else ...[
                // Saisie manuelle
                TextFormField(
                  controller: _manualUidController,
                  textCapitalization: TextCapitalization.characters,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    labelText:
                        widget.isReassign ? 'Nouveau token UID' : 'Token UID',
                    hintText: 'Ex : ST-001',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  validator: (v) {
                    if (_manualMode && (v == null || v.trim().isEmpty)) {
                      return "L'UID du bracelet est obligatoire";
                    }
                    return null;
                  },
                ),
                if (_availableTokens.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => setState(() => _manualMode = false),
                      child: const Text(
                        'Choisir dans la liste',
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                  ),
                ],
              ],
              const SizedBox(height: 8),

              // Type d'assignation
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Type de bracelet',
                  border: OutlineInputBorder(),
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _assignmentType,
                    isDense: true,
                    isExpanded: true,
                    style: const TextStyle(fontSize: 13, color: Colors.black87),
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
                const SizedBox(height: 10),
                TextFormField(
                  controller: _justificationController,
                  style: const TextStyle(fontSize: 13),
                  decoration: const InputDecoration(
                    labelText: 'Justification (obligatoire)',
                    hintText: 'Ex : Bracelet endommage',
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline,
                          size: 14, color: Colors.red.shade700),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _error!,
                          style: TextStyle(
                              color: Colors.red.shade800, fontSize: 12),
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
          child: const Text('Annuler', style: TextStyle(fontSize: 13)),
        ),
        FilledButton(
          onPressed: _isLoading ? null : _submit,
          child: _isLoading
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : Text(
                  widget.isReassign ? 'Reassigner' : 'Assigner',
                  style: const TextStyle(fontSize: 13),
                ),
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
      final uid = _manualMode
          ? _manualUidController.text.trim().toUpperCase()
          : _selectedTokenUid!;

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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.person_outline, size: 16),
          const SizedBox(width: 6),
          Text(
            '${student.lastName} ${student.firstName}',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          if (student.email != null) ...[
            const SizedBox(width: 8),
            Text(
              student.email!,
              style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }
}
