import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html; // ignore: deprecated_member_use

import '../../../core/api/api_client.dart';
import '../providers/audit_provider.dart';

/// Ecran de consultation des logs d'audit (US 6.4).
/// Reserve a la Direction et Admin Tech.
class AuditLogScreen extends StatefulWidget {
  const AuditLogScreen({super.key});

  @override
  State<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends State<AuditLogScreen> {
  late final AuditProvider _provider;

  // Controleurs pour les filtres
  final _actionController = TextEditingController();
  final _resourceTypeController = TextEditingController();
  DateTime? _dateFrom;
  DateTime? _dateTo;

  @override
  void initState() {
    super.initState();
    _provider = AuditProvider();
    _provider.loadLogs();
  }

  @override
  void dispose() {
    _actionController.dispose();
    _resourceTypeController.dispose();
    _provider.dispose();
    super.dispose();
  }

  /// Actions disponibles pour le filtre dropdown.
  static const _actionOptions = [
    '',
    'LOGIN_SUCCESS',
    'LOGIN_FAILED',
    'LOGIN_LOCKED',
    'PASSWORD_CHANGED',
    '2FA_ENABLED',
    '2FA_DISABLED',
    'USER_CREATED',
    'USER_DELETED',
    'STUDENT_CREATED',
    'STUDENT_UPDATED',
    'STUDENT_DELETED',
    'STUDENTS_IMPORTED',
    'TRIP_CREATED',
    'TRIP_UPDATED',
    'TRIP_ARCHIVED',
    'CLASS_CREATED',
    'CLASS_UPDATED',
    'CLASS_DELETED',
    'TOKEN_ASSIGNED',
    'TOKEN_REASSIGNED',
    'TOKENS_RELEASED',
    'ASSIGNMENTS_EXPORTED',
    'ATTENDANCES_EXPORTED',
    'ATTENDANCES_BULK_EXPORTED',
    'CHECKPOINT_CREATED',
    'CHECKPOINT_CLOSED',
    'SYNC_ATTENDANCES',
    'QR_EMAILS_SENT',
    'AUDIT_LOGS_EXPORTED',
  ];

  /// Types de ressource disponibles pour le filtre dropdown.
  static const _resourceTypeOptions = [
    '',
    'AUTH',
    'USER',
    'STUDENT',
    'TRIP',
    'CLASS',
    'ASSIGNMENT',
    'CHECKPOINT',
    'ATTENDANCE',
    'AUDIT',
  ];

  void _applyFilters() {
    _provider.applyFilters(
      action: _actionController.text.isEmpty ? null : _actionController.text,
      resourceType: _resourceTypeController.text.isEmpty ? null : _resourceTypeController.text,
      dateFrom: _dateFrom != null
          ? '${_dateFrom!.year}-${_dateFrom!.month.toString().padLeft(2, '0')}-${_dateFrom!.day.toString().padLeft(2, '0')}'
          : null,
      dateTo: _dateTo != null
          ? '${_dateTo!.year}-${_dateTo!.month.toString().padLeft(2, '0')}-${_dateTo!.day.toString().padLeft(2, '0')}'
          : null,
    );
  }

  void _clearFilters() {
    _actionController.clear();
    _resourceTypeController.clear();
    setState(() {
      _dateFrom = null;
      _dateTo = null;
    });
    _provider.clearFilters();
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final initial = isFrom ? _dateFrom : _dateTo;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial ?? DateTime.now(),
      firstDate: DateTime(2025),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        if (isFrom) {
          _dateFrom = picked;
        } else {
          _dateTo = picked;
        }
      });
    }
  }

  Future<void> _exportJson() async {
    final token = ApiClient.authToken;
    if (token == null) return;

    try {
      final response = await http.get(
        Uri.parse(_provider.exportUrl),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode != 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erreur export : ${response.statusCode}')),
          );
        }
        return;
      }

      // Cree un blob et declenche le telechargement
      final blob = html.Blob([response.bodyBytes], 'application/json');
      final url = html.Url.createObjectUrlFromBlob(blob);
      html.AnchorElement(href: url)
        ..setAttribute('download', 'audit_logs.json')
        ..click();
      html.Url.revokeObjectUrl(url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur export : $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _provider,
      child: Consumer<AuditProvider>(
        builder: (context, provider, _) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Barre de filtres
                _buildFilterBar(provider),
                const SizedBox(height: 16),

                // Info resultats + export
                _buildResultsBar(provider),
                const SizedBox(height: 8),

                // Table des logs
                Expanded(child: _buildLogsTable(provider)),

                // Pagination
                if (provider.totalPages > 1) _buildPagination(provider),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildFilterBar(AuditProvider provider) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.end,
          children: [
            // Filtre action
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<String>(
                value: _actionController.text.isEmpty ? '' : _actionController.text,
                decoration: const InputDecoration(
                  labelText: 'Action',
                  isDense: true,
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                items: _actionOptions
                    .map((a) => DropdownMenuItem(
                          value: a,
                          child: Text(
                            a.isEmpty ? 'Toutes' : a,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ))
                    .toList(),
                onChanged: (v) => _actionController.text = v ?? '',
              ),
            ),

            // Filtre resource type
            SizedBox(
              width: 180,
              child: DropdownButtonFormField<String>(
                value: _resourceTypeController.text.isEmpty ? '' : _resourceTypeController.text,
                decoration: const InputDecoration(
                  labelText: 'Ressource',
                  isDense: true,
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                items: _resourceTypeOptions
                    .map((r) => DropdownMenuItem(
                          value: r,
                          child: Text(
                            r.isEmpty ? 'Toutes' : r,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ))
                    .toList(),
                onChanged: (v) => _resourceTypeController.text = v ?? '',
              ),
            ),

            // Date de debut
            SizedBox(
              width: 160,
              child: InkWell(
                onTap: () => _pickDate(isFrom: true),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Du',
                    isDense: true,
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    suffixIcon: Icon(Icons.calendar_today, size: 16),
                  ),
                  child: Text(
                    _dateFrom != null
                        ? '${_dateFrom!.day.toString().padLeft(2, '0')}/${_dateFrom!.month.toString().padLeft(2, '0')}/${_dateFrom!.year}'
                        : '',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ),
            ),

            // Date de fin
            SizedBox(
              width: 160,
              child: InkWell(
                onTap: () => _pickDate(isFrom: false),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Au',
                    isDense: true,
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    suffixIcon: Icon(Icons.calendar_today, size: 16),
                  ),
                  child: Text(
                    _dateTo != null
                        ? '${_dateTo!.day.toString().padLeft(2, '0')}/${_dateTo!.month.toString().padLeft(2, '0')}/${_dateTo!.year}'
                        : '',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ),
            ),

            // Boutons
            FilledButton.icon(
              onPressed: _applyFilters,
              icon: const Icon(Icons.search, size: 18),
              label: const Text('Filtrer'),
            ),
            OutlinedButton.icon(
              onPressed: _clearFilters,
              icon: const Icon(Icons.clear, size: 18),
              label: const Text('Reset'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultsBar(AuditProvider provider) {
    return Row(
      children: [
        Text(
          '${provider.total} resultat${provider.total > 1 ? 's' : ''}',
          style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
        ),
        const Spacer(),
        OutlinedButton.icon(
          onPressed: provider.isLoading ? null : _exportJson,
          icon: const Icon(Icons.download, size: 18),
          label: const Text('Export JSON'),
        ),
      ],
    );
  }

  Widget _buildLogsTable(AuditProvider provider) {
    if (provider.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (provider.error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
            const SizedBox(height: 8),
            Text(provider.error!, style: TextStyle(color: Colors.red.shade700)),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: provider.loadLogs,
              child: const Text('Reessayer'),
            ),
          ],
        ),
      );
    }

    if (provider.logs.isEmpty) {
      return Center(
        child: Text(
          'Aucun log trouvé.',
          style: TextStyle(color: Colors.grey.shade500, fontSize: 15),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(
            Theme.of(context).colorScheme.surfaceContainerLow,
          ),
          columnSpacing: 20,
          dataRowMinHeight: 40,
          dataRowMaxHeight: 56,
          columns: const [
            DataColumn(label: Text('Date', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
            DataColumn(label: Text('Action', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
            DataColumn(label: Text('Utilisateur', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
            DataColumn(label: Text('Ressource', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
            DataColumn(label: Text('IP', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
            DataColumn(label: Text('Details', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
          ],
          rows: provider.logs.map((log) => _buildRow(log)).toList(),
        ),
      ),
    );
  }

  DataRow _buildRow(Map<String, dynamic> log) {
    final performedAt = log['performed_at'] as String? ?? '';
    final displayDate = _formatDate(performedAt);
    final action = log['action'] as String? ?? '';
    final userEmail = log['user_email'] as String? ?? '-';
    final resourceType = log['resource_type'] as String? ?? '-';
    final ipAddress = log['ip_address'] as String? ?? '-';
    final details = log['details'] as Map<String, dynamic>?;
    final detailsStr = details != null
        ? details.entries.map((e) => '${e.key}: ${e.value}').join(', ')
        : '-';

    return DataRow(cells: [
      DataCell(Text(displayDate, style: const TextStyle(fontSize: 12))),
      DataCell(_ActionChip(action: action)),
      DataCell(Text(userEmail, style: const TextStyle(fontSize: 12))),
      DataCell(Text(resourceType, style: const TextStyle(fontSize: 12))),
      DataCell(Text(ipAddress, style: const TextStyle(fontSize: 12))),
      DataCell(
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 300),
          child: Tooltip(
            message: detailsStr,
            child: Text(
              detailsStr,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    ]);
  }

  Widget _buildPagination(AuditProvider provider) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            onPressed: provider.page > 1 ? provider.previousPage : null,
            icon: const Icon(Icons.chevron_left),
          ),
          Text(
            'Page ${provider.page} / ${provider.totalPages}',
            style: const TextStyle(fontSize: 13),
          ),
          IconButton(
            onPressed: provider.page < provider.totalPages ? provider.nextPage : null,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }

  String _formatDate(String isoDate) {
    if (isoDate.isEmpty) return '-';
    try {
      final dt = DateTime.parse(isoDate);
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} '
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return isoDate;
    }
  }
}

/// Chip colore selon la categorie de l'action.
class _ActionChip extends StatelessWidget {
  final String action;

  const _ActionChip({required this.action});

  @override
  Widget build(BuildContext context) {
    final (color, bgColor) = _actionColors(action);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        action,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }

  (Color, Color) _actionColors(String action) {
    if (action.startsWith('LOGIN_FAILED') || action.startsWith('LOGIN_LOCKED') || action.contains('FAILED')) {
      return (Colors.red.shade800, Colors.red.shade50);
    }
    if (action.startsWith('LOGIN_SUCCESS')) {
      return (Colors.green.shade800, Colors.green.shade50);
    }
    if (action.contains('DELETED') || action.contains('REMOVED')) {
      return (Colors.orange.shade800, Colors.orange.shade50);
    }
    if (action.contains('CREATED') || action.contains('ASSIGNED') || action.contains('IMPORTED')) {
      return (Colors.blue.shade800, Colors.blue.shade50);
    }
    if (action.contains('EXPORTED')) {
      return (Colors.purple.shade800, Colors.purple.shade50);
    }
    return (Colors.grey.shade800, Colors.grey.shade100);
  }
}
