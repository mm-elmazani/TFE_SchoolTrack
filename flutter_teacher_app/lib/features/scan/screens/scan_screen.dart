/// Écran principal de scan hybride QR + NFC (US 2.2).
///
/// Affiche la caméra pour lire les QR codes (physique et digital),
/// écoute en parallèle les tags NFC.
/// Montre un feedback visuel (Lottie) et sonore (audioplayers) après chaque scan.
library;

import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
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
  MobileScannerController? _cameraController;
  Timer? _resultTimer;

  @override
  void initState() {
    super.initState();
    _provider = ScanProvider(
      tripId: widget.tripId,
      checkpointId: widget.checkpointId,
      audioPlayer: AudioPlayer(),
    );
    _provider.addListener(_onProviderStateChanged);
    // Demarrer en mode QR par defaut → camera active
    _cameraController = MobileScannerController();
    _initSession();
  }

  /// Écoute les changements d'état pour auto-résumer après les scans NFC.
  /// (Les scans QR passent aussi par ici, mais _scheduleResume annule le timer précédent.)
  void _onProviderStateChanged() {
    final s = _provider.state;
    if (s == ScanState.success || s == ScanState.duplicate || s == ScanState.error) {
      _scheduleResume();
    }
  }

  Future<void> _initSession() async {
    final students = await LocalDb.instance.getStudents(widget.tripId);
    await _provider.startSession(students);

    // Restaurer le mode NFC si c'était la préférence sauvegardée
    if (_provider.scanMode == ScanMode.nfc) {
      _cameraController?.dispose();
      _cameraController = null;
      await _provider.startNfc();
    }

    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _resultTimer?.cancel();
    _provider.removeListener(_onProviderStateChanged);
    _provider.dispose();
    _cameraController?.dispose();
    super.dispose();
  }

  /// Bascule entre mode QR et NFC.
  Future<void> _switchMode(ScanMode mode) async {
    if (_provider.scanMode == mode) return;

    if (mode == ScanMode.nfc) {
      // Arreter la camera AVANT de demarrer le NFC
      await _cameraController?.stop();
      _cameraController?.dispose();
      _cameraController = null;

      final ok = await _provider.setScanMode(ScanMode.nfc);
      if (!ok && mounted) {
        // NFC non disponible → revenir en mode QR
        _cameraController = MobileScannerController();
        await _provider.setScanMode(ScanMode.qr);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('NFC non disponible sur cet appareil')),
          );
        }
      }
    } else {
      // Arreter le NFC AVANT de redemarrer la camera
      await _provider.setScanMode(ScanMode.qr);
      _cameraController = MobileScannerController();
    }
    if (mounted) setState(() {});
  }

  /// Affiche le dialog de confirmation de clôture du checkpoint (US 2.7).
  Future<void> _showCloseDialog(BuildContext context) async {
    // Capturer le navigator avant tout await pour éviter l'accès async au context.
    final nav = Navigator.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Clôturer le checkpoint ?'),
        content: Text(
          'Le checkpoint "${widget.checkpointName}" sera marqué comme terminé.\n\n'
          'Aucun nouveau scan ne sera possible après la clôture.',
        ),
        actions: [
          TextButton(
            onPressed: () => nav.pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () => nav.pop(true),
            child: const Text('Clôturer'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await _provider.closeCheckpoint();
      if (mounted) nav.pop(); // Retour à la sélection des checkpoints
    }
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
          final isQr = provider.scanMode == ScanMode.qr;
          return Scaffold(
            appBar: _buildAppBar(context, provider),
            body: Stack(
              children: [
                // Zone principale : camera QR ou UI NFC dediee
                if (isQr) _buildCamera(provider) else _buildNfcView(context, provider),

                // Overlay scan avec cadre de visee (QR uniquement)
                if (isQr) _buildScanOverlay(context, provider),

                // Panneau resultat (glisse depuis le bas quand il y a un resultat)
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

                // Toggle QR / NFC en bas
                Positioned(
                  bottom: 16,
                  left: 0,
                  right: 0,
                  child: _buildModeToggle(context, provider),
                ),
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
        // Bouton suivi présences (US 2.3)
        IconButton(
          icon: const Icon(Icons.people),
          tooltip: 'Voir les présences',
          onPressed: () => context.push('/attendance', extra: {
            'provider': _provider,
            'checkpointName': widget.checkpointName,
            'tripDestination': widget.tripDestination,
          }),
        ),
        // Bouton clôturer checkpoint (US 2.7) — visible uniquement sur ACTIVE
        if (provider.checkpointStatus == 'ACTIVE')
          TextButton(
            onPressed: () => _showCloseDialog(context),
            child: const Text(
              'Clôturer',
              style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
            ),
          ),
        const SizedBox(width: 8),
      ],
    );
  }

  // ----------------------------------------------------------------
  // Caméra
  // ----------------------------------------------------------------

  Widget _buildCamera(ScanProvider provider) {
    if (_cameraController == null) return const SizedBox.expand();
    return MobileScanner(
      controller: _cameraController!,
      onDetect: provider.qrPaused ? null : _onQrDetected,
    );
  }

  // ----------------------------------------------------------------
  // Vue NFC dediee (remplace la camera en mode NFC)
  // ----------------------------------------------------------------

  Widget _buildNfcView(BuildContext context, ScanProvider provider) {
    final cs = Theme.of(context).colorScheme;
    final isListening = provider.nfcAvailable;

    return Container(
      color: cs.surfaceContainerHighest,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icone NFC animee (pulse via TweenAnimationBuilder)
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.8, end: 1.0),
              duration: const Duration(milliseconds: 1200),
              curve: Curves.easeInOut,
              builder: (_, scale, child) => Transform.scale(scale: scale, child: child),
              onEnd: () {}, // l'animation se relance via le rebuild
              child: Icon(
                Icons.contactless_outlined,
                size: 120,
                color: isListening ? cs.primary : Colors.grey,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              isListening
                  ? 'Approchez le bracelet NFC'
                  : 'Demarrage du NFC...',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: isListening ? cs.onSurface : Colors.grey,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              isListening
                  ? 'Placez le bracelet contre le dos du telephone'
                  : 'Veuillez patienter',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey.shade600,
                  ),
            ),
            if (!isListening) ...[
              const SizedBox(height: 16),
              const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ],
        ),
      ),
    );
  }

  // ----------------------------------------------------------------
  // Toggle QR / NFC
  // ----------------------------------------------------------------

  Widget _buildModeToggle(BuildContext context, ScanProvider provider) {
    // Ne pas afficher le toggle par-dessus un panneau de resultat
    if (provider.state != ScanState.idle) return const SizedBox.shrink();

    final isQr = provider.scanMode == ScanMode.qr;
    return Center(
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(32),
        ),
        padding: const EdgeInsets.all(4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ModeButton(
              icon: Icons.qr_code_scanner,
              label: 'QR Code',
              isActive: isQr,
              onTap: () => _switchMode(ScanMode.qr),
            ),
            _ModeButton(
              icon: Icons.nfc,
              label: 'NFC',
              isActive: !isQr,
              onTap: () => _switchMode(ScanMode.nfc),
            ),
          ],
        ),
      ),
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
              child: const Text(
                'Scannez le QR code du bracelet',
                style: TextStyle(color: Colors.white, fontSize: 14),
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

// ----------------------------------------------------------------
// Bouton du toggle mode QR / NFC
// ----------------------------------------------------------------

class _ModeButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _ModeButton({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: isActive ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(28),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 20,
              color: isActive ? Colors.black87 : Colors.white60,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                color: isActive ? Colors.black87 : Colors.white60,
              ),
            ),
          ],
        ),
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
