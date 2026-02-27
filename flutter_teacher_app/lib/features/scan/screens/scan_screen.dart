/// Écran principal de scan hybride QR + NFC (US 2.2).
///
/// Affiche la caméra pour lire les QR codes (physique et digital),
/// écoute en parallèle les tags NFC.
/// Montre un feedback visuel (Lottie) et sonore (audioplayers) après chaque scan.
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import '../../../core/database/local_db.dart';
import '../providers/scan_provider.dart';

/// Écran de scan : reçoit tripId, tripDestination, checkpointId, checkpointName
/// via GoRouter extra (Map de String vers String).
class ScanScreen extends StatefulWidget {
  final String tripId;
  final String tripDestination;
  final String checkpointId;
  final String checkpointName;

  const ScanScreen({
    super.key,
    required this.tripId,
    required this.tripDestination,
    required this.checkpointId,
    required this.checkpointName,
  });

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  late ScanProvider _provider;
  final MobileScannerController _cameraController = MobileScannerController();
  Timer? _resultTimer;

  @override
  void initState() {
    super.initState();
    _provider = ScanProvider(
      tripId: widget.tripId,
      checkpointId: widget.checkpointId,
    );
    _initSession();
  }

  Future<void> _initSession() async {
    final students = await LocalDb.instance.getStudents(widget.tripId);
    await _provider.startSession(students);
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _resultTimer?.cancel();
    _provider.dispose();
    _cameraController.dispose();
    super.dispose();
  }

  void _onQrDetected(BarcodeCapture capture) {
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null || raw.isEmpty) return;
    _provider.onQrDetected(raw).then((_) => _scheduleResume());
  }

  /// Remet le scanner en idle après 2,5 secondes d'affichage du résultat.
  void _scheduleResume() {
    _resultTimer?.cancel();
    _resultTimer = Timer(const Duration(milliseconds: 2500), () {
      if (mounted) _provider.resumeScanning();
    });
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _provider,
      child: Consumer<ScanProvider>(
        builder: (context, provider, _) {
          return Scaffold(
            appBar: _buildAppBar(context, provider),
            body: Stack(
              children: [
                // Caméra QR (toujours visible en arrière-plan)
                _buildCamera(provider),

                // Overlay scan avec cadre de visée
                _buildScanOverlay(context, provider),

                // Panneau résultat (glisse depuis le bas quand il y a un résultat)
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                  bottom: provider.state != ScanState.idle ? 0 : -300,
                  left: 0,
                  right: 0,
                  child: _buildResultPanel(context, provider),
                ),

                // Compteur en haut
                _buildCounter(context, provider),
              ],
            ),
          );
        },
      ),
    );
  }

  // ----------------------------------------------------------------
  // AppBar
  // ----------------------------------------------------------------

  AppBar _buildAppBar(BuildContext context, ScanProvider provider) {
    return AppBar(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.checkpointName),
          Text(
            widget.tripDestination,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onPrimary
                      .withAlpha(200),
                ),
          ),
        ],
      ),
      backgroundColor: Theme.of(context).colorScheme.primary,
      foregroundColor: Theme.of(context).colorScheme.onPrimary,
      actions: [
        // Indicateur NFC
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Chip(
            avatar: Icon(
              Icons.nfc,
              size: 16,
              color: provider.nfcAvailable ? Colors.green : Colors.grey,
            ),
            label: Text(
              provider.nfcAvailable ? 'NFC actif' : 'NFC off',
              style: const TextStyle(fontSize: 11),
            ),
            visualDensity: VisualDensity.compact,
          ),
        ),
      ],
    );
  }

  // ----------------------------------------------------------------
  // Caméra
  // ----------------------------------------------------------------

  Widget _buildCamera(ScanProvider provider) {
    return MobileScanner(
      controller: _cameraController,
      onDetect: provider.qrPaused ? null : _onQrDetected,
    );
  }

  // ----------------------------------------------------------------
  // Overlay scan (cadre de visée + instructions)
  // ----------------------------------------------------------------

  Widget _buildScanOverlay(BuildContext context, ScanProvider provider) {
    return Positioned.fill(
      child: Column(
        children: [
          // Zone sombre en haut
          Expanded(flex: 1, child: _darkOverlay()),
          // Ligne centrale avec cadre de visée
          Row(
            children: [
              Expanded(flex: 1, child: _darkOverlay()),
              // Cadre de visée 250×250
              Container(
                width: 250,
                height: 250,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: _frameColor(provider.state),
                    width: 3,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: provider.state == ScanState.scanning
                    ? const Center(child: CircularProgressIndicator())
                    : null,
              ),
              Expanded(flex: 1, child: _darkOverlay()),
            ],
          ),
          // Zone sombre en bas avec instruction
          Expanded(
            flex: 2,
            child: Container(
              color: Colors.black54,
              alignment: Alignment.topCenter,
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                provider.nfcAvailable
                    ? 'Scannez le QR ou approchez le bracelet NFC'
                    : 'Scannez le QR code',
                style: const TextStyle(color: Colors.white, fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _darkOverlay() => ColoredBox(color: Colors.black54);

  Color _frameColor(ScanState state) => switch (state) {
        ScanState.success => Colors.green,
        ScanState.duplicate => Colors.orange,
        ScanState.error => Colors.red,
        _ => Colors.white,
      };

  // ----------------------------------------------------------------
  // Panneau résultat (glisse depuis le bas)
  // ----------------------------------------------------------------

  Widget _buildResultPanel(BuildContext context, ScanProvider provider) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(color: Colors.black26, blurRadius: 16, spreadRadius: 2),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: switch (provider.state) {
        ScanState.success => _SuccessCard(result: provider.lastResult!),
        ScanState.duplicate => _DuplicateCard(result: provider.lastResult!),
        ScanState.error => _ErrorCard(
            message: provider.lastError ?? 'Erreur inconnue',
            uid: provider.lastErrorUid,
          ),
        _ => const SizedBox(height: 80),
      },
    );
  }

  // ----------------------------------------------------------------
  // Compteur présents/manquants
  // ----------------------------------------------------------------

  Widget _buildCounter(BuildContext context, ScanProvider provider) {
    return Positioned(
      top: 8,
      right: 8,
      child: Card(
        color: Theme.of(context).colorScheme.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle_outline,
                  size: 16,
                  color: Theme.of(context).colorScheme.onPrimaryContainer),
              const SizedBox(width: 4),
              Text(
                '${provider.presentCount} / ${provider.totalStudents}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------
// Carte succès
// ----------------------------------------------------------------

class _SuccessCard extends StatelessWidget {
  final ScannedStudentInfo result;

  const _SuccessCard({required this.result});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Animation Lottie succès
        SizedBox(
          width: 72,
          height: 72,
          child: _LottieOrIcon(
            assetPath: 'assets/animations/success.json',
            fallbackIcon: Icons.check_circle,
            fallbackColor: Colors.green,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                result.fullName,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  _ScanMethodBadge(method: result.scanMethod),
                  const SizedBox(width: 8),
                  Text(
                    'Présence enregistrée',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Colors.green.shade700),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ----------------------------------------------------------------
// Carte doublon
// ----------------------------------------------------------------

class _DuplicateCard extends StatelessWidget {
  final ScannedStudentInfo result;

  const _DuplicateCard({required this.result});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 72,
          height: 72,
          child: _LottieOrIcon(
            assetPath: 'assets/animations/warning.json',
            fallbackIcon: Icons.warning_amber_rounded,
            fallbackColor: Colors.orange,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                result.fullName,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  _ScanMethodBadge(method: result.scanMethod),
                  const SizedBox(width: 8),
                  Text(
                    'Scan n°${result.scanSequence} — déjà présent',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Colors.orange.shade700),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ----------------------------------------------------------------
// Carte erreur
// ----------------------------------------------------------------

class _ErrorCard extends StatelessWidget {
  final String message;
  final String? uid;

  const _ErrorCard({required this.message, this.uid});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 72,
          height: 72,
          child: _LottieOrIcon(
            assetPath: 'assets/animations/error.json',
            fallbackIcon: Icons.cancel,
            fallbackColor: Colors.red,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Badge non reconnu',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.red.shade700,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                message,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (uid != null) ...[
                const SizedBox(height: 4),
                Text(
                  'UID: $uid',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        color: Colors.grey,
                      ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ----------------------------------------------------------------
// Badge méthode de scan
// ----------------------------------------------------------------

class _ScanMethodBadge extends StatelessWidget {
  final String method;

  const _ScanMethodBadge({required this.method});

  @override
  Widget build(BuildContext context) {
    final (icon, label) = switch (method) {
      'NFC_PHYSICAL' => ('📲', 'NFC'),
      'QR_PHYSICAL' => ('📷', 'QR'),
      'QR_DIGITAL' => ('📧', 'QR digital'),
      _ => ('👤', 'Manuel'),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Text(
        '$icon $label',
        style: const TextStyle(fontSize: 11),
      ),
    );
  }
}

// ----------------------------------------------------------------
// Widget Lottie avec fallback icône
// ----------------------------------------------------------------

class _LottieOrIcon extends StatelessWidget {
  final String assetPath;
  final IconData fallbackIcon;
  final Color fallbackColor;

  const _LottieOrIcon({
    required this.assetPath,
    required this.fallbackIcon,
    required this.fallbackColor,
  });

  @override
  Widget build(BuildContext context) {
    return Lottie.asset(
      assetPath,
      fit: BoxFit.contain,
      repeat: false,
      errorBuilder: (context, error, stackTrace) => Icon(
        fallbackIcon,
        size: 56,
        color: fallbackColor,
      ),
    );
  }
}
