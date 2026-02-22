// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/api/api_client.dart';
import '../providers/token_provider.dart';
import '../widgets/assign_token_dialog.dart';

/// Écran US 1.5 — Assignation des bracelets NFC/QR aux élèves.
///
/// Permet à la Direction de :
///   - Sélectionner un voyage
///   - Visualiser les élèves assignés / non assignés
///   - Assigner ou réassigner un bracelet par élève
///   - Exporter la liste des assignations en CSV
class TokenScreen extends StatelessWidget {
  const TokenScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => TokenProvider()..loadTrips(),
      child: const _TokenScreenBody(),
    );
  }
}

// ----------------------------------------------------------------
// Corps principal
// ----------------------------------------------------------------

class _TokenScreenBody extends StatelessWidget {
  const _TokenScreenBody();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TokenProvider>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Sélecteur de voyage + boutons d'action
        const _TripSelectorRow(),
        const SizedBox(height: 24),

        // Contenu selon l'état du provider
        if (provider.state == TokenLoadState.loadingTrips)
          const _LoadingView(message: 'Chargement des voyages...')
        else if (provider.state == TokenLoadState.loadingStudents)
          const _LoadingView(message: 'Chargement des élèves...')
        else if (provider.state == TokenLoadState.error)
          _ErrorCard(message: provider.errorMessage ?? 'Erreur inconnue')
        else if (provider.selectedTrip == null)
          const _EmptyStateCard()
        else if (provider.studentsData != null) ...[
          _StatsRow(data: provider.studentsData!),
          const SizedBox(height: 16),
          _StudentsTable(data: provider.studentsData!),
        ],
      ],
    );
  }
}

// ----------------------------------------------------------------
// Sélecteur de voyage + export
// ----------------------------------------------------------------

class _TripSelectorRow extends StatelessWidget {
  const _TripSelectorRow();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TokenProvider>();
    final isLoadingTrips = provider.state == TokenLoadState.loadingTrips;

    return Row(
      children: [
        // Dropdown de sélection du voyage
        Expanded(
          child: InputDecorator(
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              isDense: true,
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<TripSummary>(
                value: provider.selectedTrip,
                isDense: true,
                isExpanded: true,
                hint: const Text('Sélectionner un voyage'),
                items: provider.trips
                    .map(
                      (t) => DropdownMenuItem(
                        value: t,
                        child: Text(t.label),
                      ),
                    )
                    .toList(),
                onChanged: isLoadingTrips
                    ? null
                    : (trip) {
                        if (trip != null) {
                          context.read<TokenProvider>().selectTrip(trip);
                        }
                      },
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),

        // Bouton rafraîchir
        IconButton(
          onPressed: provider.selectedTrip != null
              ? () => context.read<TokenProvider>().refresh()
              : null,
          icon: const Icon(Icons.refresh),
          tooltip: 'Rafraîchir',
        ),
        const SizedBox(width: 4),

        // Bouton export CSV
        OutlinedButton.icon(
          onPressed: provider.exportUrl != null
              ? () => html.window.open(provider.exportUrl!, '_blank')
              : null,
          icon: const Icon(Icons.download, size: 18),
          label: const Text('Exporter CSV'),
        ),
        const SizedBox(width: 8),

        // Bouton libérer tous les bracelets du voyage
        _ReleaseButton(provider: provider),
      ],
    );
  }
}

// ----------------------------------------------------------------
// Statistiques (cartes en-tête)
// ----------------------------------------------------------------

class _StatsRow extends StatelessWidget {
  final TripStudentsData data;

  const _StatsRow({required this.data});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _StatCard(
          label: 'Total',
          value: '${data.total}',
          icon: Icons.people,
          color: Colors.blueGrey,
        ),
        const SizedBox(width: 12),
        _StatCard(
          label: 'Assignés',
          value: '${data.assigned}',
          icon: Icons.check_circle,
          color: Colors.green,
        ),
        const SizedBox(width: 12),
        _StatCard(
          label: 'Non assignés',
          value: '${data.unassigned}',
          icon: Icons.radio_button_unchecked,
          color: Colors.orange,
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              Text(
                label,
                style:
                    TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------
// Tableau des élèves (avec tri sur toutes les colonnes)
// ----------------------------------------------------------------

class _StudentsTable extends StatefulWidget {
  final TripStudentsData data;

  const _StudentsTable({required this.data});

  @override
  State<_StudentsTable> createState() => _StudentsTableState();
}

class _StudentsTableState extends State<_StudentsTable> {
  // Colonnes : 0=Nom  1=Prénom  2=Token UID  3=Type  4=Statut assignation
  int _sortColumnIndex = 0;
  bool _sortAscending = true;

  /// Retourne la liste triée selon la colonne et le sens courants.
  List<TripStudentInfo> get _sorted {
    final list = List<TripStudentInfo>.from(widget.data.students);
    list.sort((a, b) {
      final cmp = switch (_sortColumnIndex) {
        0 => a.lastName.compareTo(b.lastName),
        1 => a.firstName.compareTo(b.firstName),
        2 => (a.tokenUid ?? '').compareTo(b.tokenUid ?? ''),
        3 => (a.assignmentType ?? '').compareTo(b.assignmentType ?? ''),
        4 => (a.isAssigned ? 1 : 0).compareTo(b.isAssigned ? 1 : 0),
        _ => 0,
      };
      return _sortAscending ? cmp : -cmp;
    });
    return list;
  }

  void _onSort(int index, bool ascending) =>
      setState(() {
        _sortColumnIndex = index;
        _sortAscending = ascending;
      });

  @override
  Widget build(BuildContext context) {
    final provider = context.read<TokenProvider>();
    final students = _sorted;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          sortColumnIndex: _sortColumnIndex,
          sortAscending: _sortAscending,
          headingRowColor: WidgetStateProperty.all(
            Theme.of(context).colorScheme.surfaceContainerLow,
          ),
          dataRowMinHeight: 48,
          dataRowMaxHeight: 56,
          columns: [
            DataColumn(
              label: const Text('Nom'),
              onSort: _onSort,
            ),
            DataColumn(
              label: const Text('Prénom'),
              onSort: _onSort,
            ),
            DataColumn(
              label: const Text('Token UID'),
              onSort: _onSort,
            ),
            DataColumn(
              label: const Text('Type'),
              onSort: _onSort,
            ),
            DataColumn(
              label: const Text('Statut'),
              onSort: _onSort,
            ),
          ],
          rows: students.map((student) {
            return DataRow(
              cells: [
                DataCell(Text(
                  student.lastName,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                )),
                DataCell(Text(student.firstName)),
                DataCell(student.tokenUid != null
                    ? Text(
                        student.tokenUid!,
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 13),
                      )
                    : Text(
                        '—',
                        style: TextStyle(color: Colors.grey.shade400),
                      )),
                DataCell(student.assignmentType != null
                    ? _TypeBadge(type: student.assignmentType!)
                    : Text('—',
                        style: TextStyle(color: Colors.grey.shade400))),
                DataCell(
                  SizedBox(
                    height: 32,
                    child: student.isAssigned
                        ? OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12),
                              textStyle: const TextStyle(fontSize: 12),
                            ),
                            onPressed: () =>
                                _showDialog(context, provider, student),
                            child: const Text('Réassigner'),
                          )
                        : FilledButton(
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12),
                              textStyle: const TextStyle(fontSize: 12),
                            ),
                            onPressed: () =>
                                _showDialog(context, provider, student),
                            child: const Text('Assigner'),
                          ),
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  /// Affiche le dialogue d'assignation ou de réassignation.
  void _showDialog(
    BuildContext context,
    TokenProvider provider,
    TripStudentInfo student,
  ) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AssignTokenDialog(
        student: student,
        isReassign: student.isAssigned,
        provider: provider,
      ),
    );
  }
}

/// Badge coloré affichant le type de bracelet.
class _TypeBadge extends StatelessWidget {
  final String type;

  const _TypeBadge({required this.type});

  static const _config = {
    'NFC_PHYSICAL': ('NFC', Color(0xFF1565C0)),
    'QR_PHYSICAL': ('QR Phys.', Color(0xFF6A1B9A)),
    'QR_DIGITAL': ('QR Digital', Color(0xFF00695C)),
  };

  @override
  Widget build(BuildContext context) {
    final info = _config[type];
    final label = info?.$1 ?? type;
    final color = info?.$2 ?? Colors.grey;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------
// États auxiliaires
// ----------------------------------------------------------------

class _LoadingView extends StatelessWidget {
  final String message;

  const _LoadingView({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 12),
          Text(message, style: TextStyle(color: Colors.grey.shade600)),
        ],
      ),
    );
  }
}

class _EmptyStateCard extends StatelessWidget {
  const _EmptyStateCard();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.badge_outlined, size: 56, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(
            'Sélectionnez un voyage pour gérer les bracelets.',
            style: TextStyle(color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;

  const _ErrorCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: Colors.red.shade700, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: Colors.red.shade800),
            ),
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------
// Bouton libérer tous les bracelets
// ----------------------------------------------------------------

/// Bouton "Libérer (N)" actif uniquement quand des bracelets sont assignés.
class _ReleaseButton extends StatelessWidget {
  final TokenProvider provider;

  const _ReleaseButton({required this.provider});

  @override
  Widget build(BuildContext context) {
    final assigned = provider.studentsData?.assigned ?? 0;
    final canRelease = provider.selectedTrip != null &&
        provider.studentsData != null &&
        assigned > 0 &&
        !provider.isReleasing;

    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.orange.shade700,
        side: BorderSide(color: Colors.orange.shade300),
      ),
      onPressed: canRelease
          ? () => showDialog<void>(
                context: context,
                barrierDismissible: false,
                builder: (_) => _ReleaseTokensDialog(provider: provider),
              )
          : null,
      icon: const Icon(Icons.lock_open_outlined, size: 18),
      label: Text(assigned > 0 ? 'Libérer ($assigned)' : 'Libérer'),
    );
  }
}

// ----------------------------------------------------------------
// Dialogue de confirmation de libération
// ----------------------------------------------------------------

/// Dialogue de confirmation avant libération en masse des bracelets (US 1.5).
class _ReleaseTokensDialog extends StatefulWidget {
  final TokenProvider provider;

  const _ReleaseTokensDialog({required this.provider});

  @override
  State<_ReleaseTokensDialog> createState() => _ReleaseTokensDialogState();
}

class _ReleaseTokensDialogState extends State<_ReleaseTokensDialog> {
  bool _isLoading = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final assigned = widget.provider.studentsData?.assigned ?? 0;
    final destination = widget.provider.selectedTrip?.destination ?? '';

    return AlertDialog(
      title: const Text('Libérer tous les bracelets ?'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RichText(
              text: TextSpan(
                style: DefaultTextStyle.of(context).style,
                children: [
                  TextSpan(text: '$assigned bracelet(s) actif(s) '),
                  const TextSpan(
                    text: 'seront libérés',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  TextSpan(text: ' pour le voyage « $destination ».'),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.warning_amber_rounded,
                    size: 16, color: Colors.orange.shade700),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Cette action ne peut pas être annulée.',
                    style: TextStyle(
                      color: Colors.orange.shade800,
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),

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
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Colors.orange.shade700,
          ),
          onPressed: _isLoading ? null : _confirm,
          child: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Text('Libérer'),
        ),
      ],
    );
  }

  /// Envoie la requête de libération et ferme le dialogue en cas de succès.
  Future<void> _confirm() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final count = await widget.provider.releaseTripTokens();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              count > 0
                  ? '$count bracelet(s) libéré(s) avec succès.'
                  : 'Aucun bracelet actif à libérer.',
            ),
            backgroundColor:
                count > 0 ? Colors.green.shade700 : Colors.grey.shade600,
            duration: const Duration(seconds: 3),
          ),
        );
      }
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
}
