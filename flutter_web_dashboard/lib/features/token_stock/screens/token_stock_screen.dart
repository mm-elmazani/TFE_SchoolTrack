// Ecran de suivi du stock de bracelets — Direction (US 1.4).
//
// Affiche :
//   - Statistiques du stock (total, disponibles, assignes, endommages, perdus)
//   - Tableau des tokens avec filtres et actions (changer statut)
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/token_stock_provider.dart';

class TokenStockScreen extends StatelessWidget {
  const TokenStockScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => TokenStockProvider()..load(),
      child: const _TokenStockBody(),
    );
  }
}

class _TokenStockBody extends StatelessWidget {
  const _TokenStockBody();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TokenStockProvider>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Stats + filtres
        _StatsRow(provider: provider),
        const SizedBox(height: 16),
        _FilterRow(provider: provider),
        const SizedBox(height: 16),

        // Contenu
        if (provider.state == TokenStockState.loading)
          const Expanded(
            child: Center(child: CircularProgressIndicator()),
          )
        else if (provider.state == TokenStockState.error)
          _ErrorCard(message: provider.errorMessage ?? 'Erreur inconnue')
        else
          Expanded(
            child: SingleChildScrollView(
              child: _TokenTable(provider: provider),
            ),
          ),
      ],
    );
  }
}

// ----------------------------------------------------------------
// Statistiques
// ----------------------------------------------------------------

class _StatsRow extends StatelessWidget {
  final TokenStockProvider provider;

  const _StatsRow({required this.provider});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _StatCard(
          label: 'Total',
          value: '${provider.total}',
          icon: Icons.inventory_2,
          color: Colors.blueGrey,
        ),
        const SizedBox(width: 12),
        _StatCard(
          label: 'Disponibles',
          value: '${provider.available}',
          icon: Icons.check_circle,
          color: Colors.green,
        ),
        const SizedBox(width: 12),
        _StatCard(
          label: 'Assignes',
          value: '${provider.assigned}',
          icon: Icons.person,
          color: Colors.orange,
        ),
        const SizedBox(width: 12),
        _StatCard(
          label: 'Endommages',
          value: '${provider.damaged}',
          icon: Icons.broken_image,
          color: Colors.red,
        ),
        const SizedBox(width: 12),
        _StatCard(
          label: 'Perdus',
          value: '${provider.lost}',
          icon: Icons.search_off,
          color: Colors.grey,
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              Text(
                label,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------
// Filtres
// ----------------------------------------------------------------

class _FilterRow extends StatelessWidget {
  final TokenStockProvider provider;

  const _FilterRow({required this.provider});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Filtre par statut
        SizedBox(
          width: 180,
          child: DropdownButtonFormField<String>(
            initialValue: provider.filterStatus,
            style: const TextStyle(fontSize: 13, color: Colors.black87),
            decoration: const InputDecoration(
              labelText: 'Statut',
              border: OutlineInputBorder(),
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            items: const [
              DropdownMenuItem(value: null, child: Text('Tous')),
              DropdownMenuItem(value: 'AVAILABLE', child: Text('Disponibles')),
              DropdownMenuItem(value: 'ASSIGNED', child: Text('Assignes')),
              DropdownMenuItem(value: 'DAMAGED', child: Text('Endommages')),
              DropdownMenuItem(value: 'LOST', child: Text('Perdus')),
            ],
            onChanged: (v) =>
                context.read<TokenStockProvider>().setFilterStatus(v),
          ),
        ),
        const SizedBox(width: 12),

        // Filtre par type
        SizedBox(
          width: 180,
          child: DropdownButtonFormField<String>(
            initialValue: provider.filterType,
            style: const TextStyle(fontSize: 13, color: Colors.black87),
            decoration: const InputDecoration(
              labelText: 'Type',
              border: OutlineInputBorder(),
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            items: const [
              DropdownMenuItem(value: null, child: Text('Tous')),
              DropdownMenuItem(
                  value: 'NFC_PHYSICAL', child: Text('NFC Physique')),
              DropdownMenuItem(
                  value: 'QR_PHYSICAL', child: Text('QR Physique')),
            ],
            onChanged: (v) =>
                context.read<TokenStockProvider>().setFilterType(v),
          ),
        ),
        const SizedBox(width: 12),

        // Bouton rafraichir
        IconButton(
          onPressed: () => context.read<TokenStockProvider>().load(),
          icon: const Icon(Icons.refresh),
          tooltip: 'Rafraichir',
        ),

        const Spacer(),

        // Compteur
        Text(
          '${provider.tokens.length} token(s)',
          style: TextStyle(color: Colors.grey.shade600),
        ),
      ],
    );
  }
}

// ----------------------------------------------------------------
// Tableau des tokens
// ----------------------------------------------------------------

class _TokenTable extends StatelessWidget {
  final TokenStockProvider provider;

  const _TokenTable({required this.provider});

  @override
  Widget build(BuildContext context) {
    if (provider.tokens.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Column(
            children: [
              Icon(Icons.inventory_2_outlined,
                  size: 56, color: Colors.grey.shade300),
              const SizedBox(height: 12),
              Text(
                'Aucun bracelet dans le stock.',
                style: TextStyle(color: Colors.grey.shade500),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(
            Theme.of(context).colorScheme.surfaceContainerLow,
          ),
          columns: const [
            DataColumn(label: Text('Token UID')),
            DataColumn(label: Text('Type')),
            DataColumn(label: Text('Statut')),
            DataColumn(label: Text('UID Hardware')),
            DataColumn(label: Text('Cree le')),
            DataColumn(label: Text('Derniere assignation')),
            DataColumn(label: Text('Actions')),
          ],
          rows: provider.tokens.map((token) {
            return DataRow(cells: [
              DataCell(Text(
                token.tokenUid,
                style: const TextStyle(
                    fontFamily: 'monospace', fontWeight: FontWeight.w600),
              )),
              DataCell(_TypeBadge(type: token.tokenType)),
              DataCell(_StatusBadge(status: token.status)),
              DataCell(Text(
                token.hardwareUid ?? '—',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: token.hardwareUid != null
                      ? Colors.black87
                      : Colors.grey.shade400,
                ),
              )),
              DataCell(Text(
                _formatDate(token.createdAt),
                style: const TextStyle(fontSize: 13),
              )),
              DataCell(Text(
                token.lastAssignedAt != null
                    ? _formatDate(token.lastAssignedAt!)
                    : '—',
                style: TextStyle(
                  fontSize: 13,
                  color: token.lastAssignedAt != null
                      ? Colors.black87
                      : Colors.grey.shade400,
                ),
              )),
              DataCell(_StatusActionButton(token: token)),
            ]);
          }).toList(),
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/'
      '${dt.month.toString().padLeft(2, '0')}/'
      '${dt.year} '
      '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}';
}

// ----------------------------------------------------------------
// Badges
// ----------------------------------------------------------------

class _TypeBadge extends StatelessWidget {
  final String type;

  const _TypeBadge({required this.type});

  static const _config = {
    'NFC_PHYSICAL': ('NFC', Color(0xFF1565C0)),
    'QR_PHYSICAL': ('QR Phys.', Color(0xFF6A1B9A)),
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

class _StatusBadge extends StatelessWidget {
  final String status;

  const _StatusBadge({required this.status});

  static const _config = {
    'AVAILABLE': ('Disponible', Colors.green),
    'ASSIGNED': ('Assigne', Colors.orange),
    'DAMAGED': ('Endommage', Colors.red),
    'LOST': ('Perdu', Colors.grey),
  };

  @override
  Widget build(BuildContext context) {
    final info = _config[status];
    final label = info?.$1 ?? status;
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
// Bouton d'action pour changer le statut
// ----------------------------------------------------------------

class _StatusActionButton extends StatelessWidget {
  final StockToken token;

  const _StatusActionButton({required this.token});

  @override
  Widget build(BuildContext context) {
    // On ne peut pas changer le statut d'un token ASSIGNED manuellement
    if (token.status == 'ASSIGNED') {
      return Text('—', style: TextStyle(color: Colors.grey.shade400));
    }

    return PopupMenuButton<String>(
      tooltip: 'Changer le statut',
      icon: const Icon(Icons.more_vert, size: 18),
      onSelected: (value) async {
        if (value == '_DELETE') {
          final confirm = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Supprimer le bracelet ?'),
              content: Text(
                'Le bracelet ${token.tokenUid} sera definitivement supprime du stock.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Annuler'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: FilledButton.styleFrom(backgroundColor: Colors.red),
                  child: const Text('Supprimer'),
                ),
              ],
            ),
          );
          if (confirm == true && context.mounted) {
            context.read<TokenStockProvider>().deleteToken(token.id);
          }
        } else {
          context.read<TokenStockProvider>().updateStatus(token.id, value);
        }
      },
      itemBuilder: (_) => [
        if (token.status != 'AVAILABLE')
          const PopupMenuItem(
            value: 'AVAILABLE',
            child: Text('Marquer disponible'),
          ),
        if (token.status != 'DAMAGED')
          const PopupMenuItem(
            value: 'DAMAGED',
            child: Text('Marquer endommage'),
          ),
        if (token.status != 'LOST')
          const PopupMenuItem(
            value: 'LOST',
            child: Text('Marquer perdu'),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: '_DELETE',
          child: Text('Supprimer', style: TextStyle(color: Colors.red)),
        ),
      ],
    );
  }
}

// ----------------------------------------------------------------
// Erreur
// ----------------------------------------------------------------

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
