/// Ecran de test de lecture NFC — Admin uniquement.
///
/// Permet de verifier le bon fonctionnement de la lecture NFC
/// en affichant les donnees brutes du tag (UID hardware, contenu NDEF, type).
library;

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nfc_manager/ndef_record.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_android.dart';

/// Resultat d'une lecture NFC de test.
class NfcTestResult {
  final String? hardwareUid;
  final String? ndefContent;
  final int? ndefRecordCount;
  final String? tagType;
  final bool isWritable;
  final int? maxSize;
  final DateTime scannedAt;
  final List<NdefRecordInfo> records;

  NfcTestResult({
    this.hardwareUid,
    this.ndefContent,
    this.ndefRecordCount,
    this.tagType,
    this.isWritable = false,
    this.maxSize,
    required this.scannedAt,
    this.records = const [],
  });
}

/// Info d'un record NDEF individuel.
class NdefRecordInfo {
  final String tnf;
  final String type;
  final String payload;
  final int payloadLength;

  NdefRecordInfo({
    required this.tnf,
    required this.type,
    required this.payload,
    required this.payloadLength,
  });
}

class NfcTestScreen extends StatefulWidget {
  const NfcTestScreen({super.key});

  @override
  State<NfcTestScreen> createState() => _NfcTestScreenState();
}

class _NfcTestScreenState extends State<NfcTestScreen> {
  bool _nfcAvailable = false;
  bool _sessionActive = false;
  bool _checking = true;
  String? _error;
  final List<NfcTestResult> _results = [];

  @override
  void initState() {
    super.initState();
    _checkNfc();
  }

  @override
  void dispose() {
    _stopSession();
    super.dispose();
  }

  Future<void> _checkNfc() async {
    try {
      final availability = await NfcManager.instance.checkAvailability();
      setState(() {
        _nfcAvailable = availability == NfcAvailability.enabled;
        _checking = false;
      });
    } catch (e) {
      setState(() {
        _nfcAvailable = false;
        _checking = false;
        _error = 'Erreur verification NFC : $e';
      });
    }
  }

  Future<void> _startSession() async {
    if (!_nfcAvailable) return;

    setState(() {
      _sessionActive = true;
      _error = null;
    });

    try {
      await NfcManager.instance.startSession(
        pollingOptions: {NfcPollingOption.iso14443},
        onDiscovered: (NfcTag tag) async {
          try {
            final result = await _readTag(tag);
            if (mounted) {
              setState(() => _results.insert(0, result));
              await HapticFeedback.lightImpact();
            }
          } catch (e) {
            if (mounted) {
              setState(() => _error = 'Erreur lecture : $e');
            }
          }
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _sessionActive = false;
          _error = 'Erreur demarrage session : $e';
        });
      }
    }
  }

  Future<void> _stopSession() async {
    if (!_sessionActive) return;
    try {
      await NfcManager.instance.stopSession();
    } catch (_) {}
    if (mounted) {
      setState(() => _sessionActive = false);
    }
  }

  Future<NfcTestResult> _readTag(NfcTag tag) async {
    // UID hardware
    String? hardwareUid;
    try {
      final androidTag = NfcTagAndroid.from(tag);
      if (androidTag != null) {
        hardwareUid = androidTag.id
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join(':')
            .toUpperCase();
      }
    } catch (_) {}

    // NDEF
    String? ndefContent;
    int? ndefRecordCount;
    bool isWritable = false;
    int? maxSize;
    final records = <NdefRecordInfo>[];

    try {
      final ndef = NdefAndroid.from(tag);
      if (ndef != null) {
        isWritable = ndef.isWritable;
        maxSize = ndef.maxSize;

        final message = ndef.cachedNdefMessage ?? await ndef.getNdefMessage();
        if (message != null && message.records.isNotEmpty) {
          ndefRecordCount = message.records.length;

          for (final record in message.records) {
            final tnfName = _tnfName(record.typeNameFormat);
            final typeStr = String.fromCharCodes(record.type);
            String payloadStr;

            // Decoder le contenu selon le type
            if (record.typeNameFormat == TypeNameFormat.wellKnown &&
                record.type.length == 1 &&
                record.type[0] == 0x54) {
              // Text Record
              payloadStr = _decodeTextRecord(record.payload) ?? '(vide)';
              ndefContent ??= payloadStr;
            } else if (record.typeNameFormat == TypeNameFormat.wellKnown &&
                record.type.length == 1 &&
                record.type[0] == 0x55) {
              // URI Record
              payloadStr = _decodeUriRecord(record.payload);
              ndefContent ??= payloadStr;
            } else {
              payloadStr = String.fromCharCodes(record.payload);
              ndefContent ??= payloadStr;
            }

            records.add(NdefRecordInfo(
              tnf: tnfName,
              type: typeStr,
              payload: payloadStr,
              payloadLength: record.payload.length,
            ));
          }
        }
      }
    } catch (_) {}

    // Type de tag
    String? tagType;
    try {
      final nfcA = NfcAAndroid.from(tag);
      if (nfcA != null) {
        tagType = 'NFC-A (ISO 14443-3A)';
        final atqa = nfcA.atqa;
        final sak = nfcA.sak;
        tagType = '$tagType | ATQA: ${atqa.map((b) => b.toRadixString(16).padLeft(2, '0')).join()} | SAK: ${sak.toRadixString(16)}';
      }
    } catch (_) {}

    return NfcTestResult(
      hardwareUid: hardwareUid,
      ndefContent: ndefContent,
      ndefRecordCount: ndefRecordCount,
      tagType: tagType,
      isWritable: isWritable,
      maxSize: maxSize,
      scannedAt: DateTime.now(),
      records: records,
    );
  }

  String _tnfName(TypeNameFormat tnf) => switch (tnf) {
        TypeNameFormat.empty => 'EMPTY',
        TypeNameFormat.wellKnown => 'WELL_KNOWN',
        TypeNameFormat.media => 'MEDIA',
        TypeNameFormat.absoluteUri => 'ABSOLUTE_URI',
        TypeNameFormat.external => 'EXTERNAL',
        TypeNameFormat.unknown => 'UNKNOWN',
        TypeNameFormat.unchanged => 'UNCHANGED',
        _ => '?',
      };

  String? _decodeTextRecord(Uint8List payload) {
    if (payload.isEmpty) return null;
    final langLength = payload[0] & 0x3F;
    if (payload.length <= 1 + langLength) return null;
    return String.fromCharCodes(payload.sublist(1 + langLength)).trim();
  }

  String _decodeUriRecord(Uint8List payload) {
    if (payload.isEmpty) return '(vide)';
    const prefixes = [
      '', 'http://www.', 'https://www.', 'http://', 'https://',
      'tel:', 'mailto:', 'ftp://anonymous:anonymous@', 'ftp://ftp.',
      'ftps://', 'sftp://', 'smb://', 'nfs://', 'ftp://', 'dav://',
      'news:', 'telnet://', 'imap:', 'rtsp://', 'urn:', 'pop:',
      'sip:', 'sips:', 'tftp:', 'btspp://', 'btl2cap://',
      'btgoep://', 'tcpobex://', 'irdaobex://', 'file://',
      'urn:epc:id:', 'urn:epc:tag:', 'urn:epc:pat:', 'urn:epc:raw:',
      'urn:epc:', 'urn:nfc:',
    ];
    final code = payload[0];
    final prefix = code < prefixes.length ? prefixes[code] : '';
    return prefix + String.fromCharCodes(payload.sublist(1));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Test NFC'),
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        actions: [
          if (_results.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: 'Vider l\'historique',
              onPressed: () => setState(() => _results.clear()),
            ),
        ],
      ),
      body: _checking
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Statut NFC + bouton
                _buildStatusCard(cs),

                // Erreur
                if (_error != null) _buildErrorBanner(),

                // Historique des lectures
                Expanded(
                  child: _results.isEmpty
                      ? _buildEmptyView()
                      : _buildResultsList(),
                ),
              ],
            ),
    );
  }

  Widget _buildStatusCard(ColorScheme cs) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _sessionActive
            ? Colors.green.shade50
            : (_nfcAvailable ? Colors.blue.shade50 : Colors.red.shade50),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _sessionActive
              ? Colors.green.shade300
              : (_nfcAvailable ? Colors.blue.shade300 : Colors.red.shade300),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                Icons.nfc,
                size: 32,
                color: _sessionActive
                    ? Colors.green.shade700
                    : (_nfcAvailable ? Colors.blue.shade700 : Colors.red.shade700),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _sessionActive
                          ? 'Session NFC active'
                          : (_nfcAvailable ? 'NFC disponible' : 'NFC non disponible'),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: _sessionActive
                            ? Colors.green.shade800
                            : (_nfcAvailable ? Colors.blue.shade800 : Colors.red.shade800),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _sessionActive
                          ? 'Approchez un tag NFC du telephone...'
                          : (_nfcAvailable
                              ? 'Pret a demarrer la lecture'
                              : 'Activez le NFC dans les parametres'),
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_nfcAvailable) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: _sessionActive
                  ? OutlinedButton.icon(
                      onPressed: _stopSession,
                      icon: const Icon(Icons.stop, size: 18),
                      label: const Text('Arreter la session'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red.shade700,
                      ),
                    )
                  : FilledButton.icon(
                      onPressed: _startSession,
                      icon: const Icon(Icons.play_arrow, size: 18),
                      label: const Text('Demarrer la lecture NFC'),
                    ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 18, color: Colors.red.shade700),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _error!,
              style: TextStyle(fontSize: 13, color: Colors.red.shade800),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.contactless_outlined, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(
            _sessionActive
                ? 'En attente d\'un tag NFC...'
                : 'Demarrez la session pour lire un tag',
            style: TextStyle(color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsList() {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      itemCount: _results.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) => _TagResultCard(
        result: _results[index],
        index: _results.length - index,
      ),
    );
  }
}

// ----------------------------------------------------------------
// Carte de resultat d'un tag
// ----------------------------------------------------------------

class _TagResultCard extends StatelessWidget {
  final NfcTestResult result;
  final int index;

  const _TagResultCard({required this.result, required this.index});

  @override
  Widget build(BuildContext context) {
    final isSchoolTrack = result.ndefContent != null &&
        (result.ndefContent!.startsWith('ST-') ||
         result.ndefContent!.startsWith('QRD-') ||
         result.ndefContent!.startsWith('QRP-'));

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSchoolTrack ? Colors.green.shade300 : Colors.grey.shade200,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // En-tete
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: isSchoolTrack
                      ? Colors.green.shade100
                      : Colors.blue.shade100,
                  child: Text(
                    '#$index',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isSchoolTrack
                          ? Colors.green.shade800
                          : Colors.blue.shade800,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        result.ndefContent ?? '(pas de contenu NDEF)',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          fontFamily: result.ndefContent != null ? 'monospace' : null,
                          color: result.ndefContent != null
                              ? Colors.black87
                              : Colors.grey.shade400,
                        ),
                      ),
                      if (isSchoolTrack)
                        Text(
                          'Token SchoolTrack',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.green.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                    ],
                  ),
                ),
                Text(
                  _formatTime(result.scannedAt),
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
              ],
            ),

            const Divider(height: 20),

            // Details
            _DetailRow(
              label: 'UID Hardware',
              value: result.hardwareUid ?? '—',
              mono: true,
            ),
            const SizedBox(height: 6),
            _DetailRow(
              label: 'Type de tag',
              value: result.tagType ?? '—',
            ),
            const SizedBox(height: 6),
            _DetailRow(
              label: 'NDEF',
              value: result.ndefRecordCount != null
                  ? '${result.ndefRecordCount} record(s) | '
                    '${result.isWritable ? "inscriptible" : "lecture seule"}'
                    '${result.maxSize != null ? " | ${result.maxSize} octets max" : ""}'
                  : 'Non NDEF',
            ),

            // Records NDEF detailles
            if (result.records.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                'Records NDEF :',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 4),
              ...result.records.map((r) => Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'TNF: ${r.tnf} | Type: ${r.type} | ${r.payloadLength} octets',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                            fontFamily: 'monospace',
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          r.payload,
                          style: const TextStyle(
                            fontSize: 13,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  )),
            ],
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}:'
      '${dt.second.toString().padLeft(2, '0')}';
}

// ----------------------------------------------------------------
// Ligne de detail
// ----------------------------------------------------------------

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool mono;

  const _DetailRow({
    required this.label,
    required this.value,
    this.mono = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontFamily: mono ? 'monospace' : null,
              fontWeight: mono ? FontWeight.w600 : null,
            ),
          ),
        ),
      ],
    );
  }
}
