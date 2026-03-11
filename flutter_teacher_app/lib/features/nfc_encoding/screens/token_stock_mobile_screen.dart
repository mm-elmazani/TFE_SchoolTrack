// Ecran de consultation du stock de bracelets — Mobile (US 1.4).
// Lecture seule : affiche stats + liste filtrable des tokens.
import 'package:flutter/material.dart';

import '../../../core/api/api_client.dart';

class TokenStockMobileScreen extends StatefulWidget {
  const TokenStockMobileScreen({super.key});

  @override
  State<TokenStockMobileScreen> createState() => _TokenStockMobileScreenState();
}

class _TokenStockMobileScreenState extends State<TokenStockMobileScreen> {
  final ApiClient _api = ApiClient();

  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _stats;
  List<Map<String, dynamic>> _tokens = [];
  String? _filterStatus;

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
      final results = await Future.wait([
        _api.getTokens(status: _filterStatus),
        _api.getTokenStats(),
      ]);
      _tokens = results[0] as List<Map<String, dynamic>>;
      _stats = results[1] as Map<String, dynamic>;
    } on ApiException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = 'Erreur inattendue : $e';
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stock de bracelets'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
            tooltip: 'Rafraichir',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorView(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _StatsSection(stats: _stats),
                      const SizedBox(height: 16),
                      _FilterChips(
                        selected: _filterStatus,
                        onChanged: (v) {
                          _filterStatus = v;
                          _load();
                        },
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '${_tokens.length} bracelet(s)',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ..._tokens.map((t) => _TokenCard(token: t)),
                      if (_tokens.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 40),
                          child: Center(
                            child: Column(
                              children: [
                                Icon(Icons.inventory_2_outlined,
                                    size: 48, color: Colors.grey.shade300),
                                const SizedBox(height: 8),
                                Text(
                                  'Aucun bracelet.',
                                  style: TextStyle(color: Colors.grey.shade500),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }
}

// ----------------------------------------------------------------
// Statistiques
// ----------------------------------------------------------------

class _StatsSection extends StatelessWidget {
  final Map<String, dynamic>? stats;

  const _StatsSection({required this.stats});

  @override
  Widget build(BuildContext context) {
    if (stats == null) return const SizedBox.shrink();

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _StatChip(label: 'Total', value: '${stats!['total'] ?? 0}', color: Colors.blueGrey),
        _StatChip(label: 'Disponibles', value: '${stats!['available'] ?? 0}', color: Colors.green),
        _StatChip(label: 'Assignes', value: '${stats!['assigned'] ?? 0}', color: Colors.orange),
        _StatChip(label: 'Endommages', value: '${stats!['damaged'] ?? 0}', color: Colors.red),
        _StatChip(label: 'Perdus', value: '${stats!['lost'] ?? 0}', color: Colors.grey),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatChip({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 16)),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 12, color: color)),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------
// Filtres
// ----------------------------------------------------------------

class _FilterChips extends StatelessWidget {
  final String? selected;
  final ValueChanged<String?> onChanged;

  const _FilterChips({required this.selected, required this.onChanged});

  static const _filters = {
    null: 'Tous',
    'AVAILABLE': 'Disponibles',
    'ASSIGNED': 'Assignes',
    'DAMAGED': 'Endommages',
    'LOST': 'Perdus',
  };

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: _filters.entries.map((e) {
        final isSelected = e.key == selected;
        return ChoiceChip(
          label: Text(e.value),
          selected: isSelected,
          onSelected: (_) => onChanged(e.key),
        );
      }).toList(),
    );
  }
}

// ----------------------------------------------------------------
// Carte token
// ----------------------------------------------------------------

class _TokenCard extends StatelessWidget {
  final Map<String, dynamic> token;

  const _TokenCard({required this.token});

  static const _statusConfig = {
    'AVAILABLE': ('Disponible', Colors.green),
    'ASSIGNED': ('Assigne', Colors.orange),
    'DAMAGED': ('Endommage', Colors.red),
    'LOST': ('Perdu', Colors.grey),
  };

  @override
  Widget build(BuildContext context) {
    final status = token['status'] as String? ?? '';
    final info = _statusConfig[status];
    final statusLabel = info?.$1 ?? status;
    final statusColor = info?.$2 ?? Colors.grey;
    final tokenType = token['token_type'] as String? ?? '';
    final isNfc = tokenType == 'NFC_PHYSICAL';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: statusColor.withValues(alpha: 0.15),
          child: Icon(
            isNfc ? Icons.nfc : Icons.qr_code,
            color: statusColor,
            size: 20,
          ),
        ),
        title: Text(
          token['token_uid'] as String? ?? '',
          style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          token['hardware_uid'] as String? ?? 'Pas d\'UID hardware',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontFamily: 'monospace'),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: statusColor.withValues(alpha: 0.4)),
          ),
          child: Text(
            statusLabel,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: statusColor),
          ),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------
// Erreur
// ----------------------------------------------------------------

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Reessayer'),
          ),
        ],
      ),
    );
  }
}
