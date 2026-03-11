/// Ecran d'encodage NFC des bracelets — Mode Admin (US 1.4).
///
/// Permet a la Direction de :
///   - Configurer le prefixe et le numero de serie de depart
///   - Ecrire l'UID NDEF sur un bracelet NTAG213
///   - Optionnellement verrouiller le tag (makeReadOnly)
///   - Visualiser l'historique des tokens encodes
///   - Consulter les stats du stock
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/nfc_encoding_provider.dart';

class NfcEncodingScreen extends StatelessWidget {
  const NfcEncodingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => NfcEncodingProvider()..init(),
      child: const _NfcEncodingBody(),
    );
  }
}

class _NfcEncodingBody extends StatelessWidget {
  const _NfcEncodingBody();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Encodage NFC'),
        actions: [
          // Badge avec le nombre de tokens encodes pendant cette session
          Consumer<NfcEncodingProvider>(
            builder: (_, p, __) => p.encodedCount > 0
                ? Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Chip(
                      avatar: const Icon(Icons.check_circle, size: 18),
                      label: Text('${p.encodedCount} encode(s)'),
                      backgroundColor:
                          Colors.green.shade100,
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
      body: const SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _StatsCard(),
              SizedBox(height: 16),
              _ConfigCard(),
              SizedBox(height: 16),
              _EncodingCard(),
              SizedBox(height: 16),
              _HistoryCard(),
            ],
          ),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------
// Statistiques du stock
// ----------------------------------------------------------------

class _StatsCard extends StatelessWidget {
  const _StatsCard();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NfcEncodingProvider>();
    final stats = provider.stats;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.inventory_2_outlined, color: Colors.blue.shade700),
                const SizedBox(width: 8),
                Text(
                  'Stock de bracelets',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 20),
                  onPressed: () => provider.loadStats(),
                  tooltip: 'Rafraichir',
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (stats == null)
              const Text(
                'Chargement...',
                style: TextStyle(color: Colors.grey),
              )
            else
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  _StatChip(
                    label: 'Total',
                    value: '${stats['total'] ?? 0}',
                    color: Colors.blueGrey,
                  ),
                  _StatChip(
                    label: 'Disponibles',
                    value: '${stats['available'] ?? 0}',
                    color: Colors.green,
                  ),
                  _StatChip(
                    label: 'Assignes',
                    value: '${stats['assigned'] ?? 0}',
                    color: Colors.orange,
                  ),
                  _StatChip(
                    label: 'Endommages',
                    value: '${stats['damaged'] ?? 0}',
                    color: Colors.red,
                  ),
                  _StatChip(
                    label: 'Perdus',
                    value: '${stats['lost'] ?? 0}',
                    color: Colors.grey,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatChip({
    required this.label,
    required this.value,
    required this.color,
  });

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
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: color,
              fontSize: 16,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: color),
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------
// Configuration (prefixe, sequence, verrouillage)
// ----------------------------------------------------------------

class _ConfigCard extends StatelessWidget {
  const _ConfigCard();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NfcEncodingProvider>();
    final isActive = provider.state != EncodingState.idle &&
        provider.state != EncodingState.error;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Configuration',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                // Prefixe
                Expanded(
                  flex: 2,
                  child: TextField(
                    enabled: !isActive,
                    decoration: const InputDecoration(
                      labelText: 'Prefixe',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    controller:
                        TextEditingController(text: provider.prefix),
                    onChanged: (v) => provider.prefix = v,
                    textCapitalization: TextCapitalization.characters,
                  ),
                ),
                const SizedBox(width: 12),
                // Numero de depart
                Expanded(
                  flex: 3,
                  child: TextField(
                    enabled: !isActive,
                    decoration: const InputDecoration(
                      labelText: 'Prochain numero',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    controller: TextEditingController(
                      text: provider.nextSequence.toString(),
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (v) {
                      final n = int.tryParse(v);
                      if (n != null) provider.nextSequence = n;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Preview du prochain UID
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.label_outline, color: Colors.blue.shade700),
                  const SizedBox(width: 8),
                  Text(
                    'Prochain : ',
                    style: TextStyle(color: Colors.blue.shade700),
                  ),
                  Text(
                    provider.nextTokenUid,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                      fontSize: 18,
                      color: Colors.blue.shade900,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Option de verrouillage
            SwitchListTile(
              title: const Text('Verrouiller le tag (read-only)'),
              subtitle: const Text(
                'Empeche toute reecriture du tag. Irreversible.',
              ),
              value: provider.lockTag,
              onChanged: isActive ? null : (v) => provider.lockTag = v,
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------
// Zone d'encodage (bouton + feedback)
// ----------------------------------------------------------------

class _EncodingCard extends StatelessWidget {
  const _EncodingCard();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NfcEncodingProvider>();
    final state = provider.state;

    return Card(
      color: _cardColor(state),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // Icone selon l'etat
            _StateIcon(state: state),
            const SizedBox(height: 16),

            // Message
            Text(
              _stateMessage(state, provider),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: _textColor(state),
                  ),
            ),

            if (provider.errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                provider.errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.red.shade700, fontSize: 13),
              ),
            ],
            const SizedBox(height: 20),

            // Bouton principal
            if (!provider.nfcAvailable)
              const _NfcUnavailableWarning()
            else if (state == EncodingState.idle ||
                state == EncodingState.error)
              FilledButton.icon(
                onPressed: () => provider.startEncoding(),
                icon: const Icon(Icons.nfc, size: 22),
                label: const Text('Demarrer l\'encodage'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 14,
                  ),
                ),
              )
            else if (state == EncodingState.waitingForTag ||
                state == EncodingState.success)
              OutlinedButton.icon(
                onPressed: () => provider.stopEncoding(),
                icon: const Icon(Icons.stop),
                label: const Text('Arreter'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 14,
                  ),
                ),
              )
            else
              const SizedBox.shrink(), // writing/registering → pas de bouton
          ],
        ),
      ),
    );
  }

  Color _cardColor(EncodingState state) => switch (state) {
        EncodingState.success => Colors.green.shade50,
        EncodingState.error => Colors.red.shade50,
        EncodingState.waitingForTag => Colors.blue.shade50,
        EncodingState.writing || EncodingState.registering =>
          Colors.orange.shade50,
        _ => Colors.white,
      };

  Color _textColor(EncodingState state) => switch (state) {
        EncodingState.success => Colors.green.shade800,
        EncodingState.error => Colors.red.shade800,
        EncodingState.waitingForTag => Colors.blue.shade800,
        _ => Colors.black87,
      };

  String _stateMessage(EncodingState state, NfcEncodingProvider provider) =>
      switch (state) {
        EncodingState.idle => 'Pret a encoder des bracelets NFC',
        EncodingState.waitingForTag =>
          'Approchez un bracelet NFC...',
        EncodingState.writing => 'Ecriture NDEF en cours...',
        EncodingState.registering => 'Enregistrement dans le serveur...',
        EncodingState.success =>
          'Bracelet encode avec succes !',
        EncodingState.error => 'Echec de l\'encodage',
      };
}

class _StateIcon extends StatelessWidget {
  final EncodingState state;

  const _StateIcon({required this.state});

  @override
  Widget build(BuildContext context) {
    return switch (state) {
      EncodingState.idle => Icon(
          Icons.nfc,
          size: 64,
          color: Colors.grey.shade400,
        ),
      EncodingState.waitingForTag => Icon(
          Icons.contactless_outlined,
          size: 64,
          color: Colors.blue.shade400,
        ),
      EncodingState.writing || EncodingState.registering => SizedBox(
          width: 48,
          height: 48,
          child: CircularProgressIndicator(
            strokeWidth: 3,
            color: Colors.orange.shade600,
          ),
        ),
      EncodingState.success => Icon(
          Icons.check_circle,
          size: 64,
          color: Colors.green.shade600,
        ),
      EncodingState.error => Icon(
          Icons.error_outline,
          size: 64,
          color: Colors.red.shade600,
        ),
    };
  }
}

class _NfcUnavailableWarning extends StatelessWidget {
  const _NfcUnavailableWarning();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange.shade300),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber, color: Colors.orange.shade700),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Le NFC n\'est pas disponible ou est desactive sur cet appareil. '
              'Activez-le dans les parametres.',
            ),
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------
// Historique des encodages de la session
// ----------------------------------------------------------------

class _HistoryCard extends StatelessWidget {
  const _HistoryCard();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NfcEncodingProvider>();
    final tokens = provider.encodedTokens;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Historique de la session (${tokens.length})',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            if (tokens.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Aucun bracelet encode pour le moment.',
                  style: TextStyle(color: Colors.grey.shade500),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: tokens.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  // Afficher du plus recent au plus ancien
                  final token = tokens[tokens.length - 1 - index];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      radius: 18,
                      backgroundColor: Colors.green.shade100,
                      child: Text(
                        '${tokens.length - index}',
                        style: TextStyle(
                          color: Colors.green.shade800,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    title: Text(
                      token.tokenUid,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      token.hardwareUid ?? 'UID hardware non lu',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                        fontFamily: 'monospace',
                      ),
                    ),
                    trailing: token.locked
                        ? Tooltip(
                            message: 'Tag verrouille',
                            child: Icon(
                              Icons.lock,
                              size: 18,
                              color: Colors.orange.shade700,
                            ),
                          )
                        : null,
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
