/// Provider gérant l'état de la session de scan (US 2.2).
library;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import '../../../core/database/local_db.dart';
import '../../../core/services/hybrid_identity_reader.dart';
import '../../../features/trips/models/offline_bundle.dart';

/// État de l'écran de scan.
enum ScanState { idle, scanning, success, duplicate, error }

/// Résumé d'un élève après scan (affiché dans l'écran de résultat).
class ScannedStudentInfo {
  final String fullName;
  final String scanMethod;
  final bool isDuplicate;
  final int scanSequence;
  final DateTime scannedAt;

  const ScannedStudentInfo({
    required this.fullName,
    required this.scanMethod,
    required this.isDuplicate,
    required this.scanSequence,
    required this.scannedAt,
  });
}

/// Provider central pour la session de scan d'un checkpoint.
class ScanProvider extends ChangeNotifier {
  final String tripId;
  final String checkpointId;
  final HybridIdentityReader _reader;

  /// null = mode silencieux (tests unitaires).
  final AudioPlayer? _audio;

  /// [audioPlayer] peut être injecté pour les tests (évite les appels platform channel).
  /// En production, passer explicitement [AudioPlayer()].
  ScanProvider({
    required this.tripId,
    required this.checkpointId,
    AudioPlayer? audioPlayer,
  })  : _audio = audioPlayer,
        _reader = HybridIdentityReader(
          tripId: tripId,
          checkpointId: checkpointId,
        );

  bool _disposed = false;
  bool _nfcAvailable = false;
  bool _qrPaused = false; // true pendant l'affichage du résultat

  ScanState _state = ScanState.idle;
  ScannedStudentInfo? _lastResult;
  String? _lastError;
  String? _lastErrorUid;

  // Compteurs en temps réel
  int _presentCount = 0;
  int _totalStudents = 0;

  // ----------------------------------------------------------------
  // Getters
  // ----------------------------------------------------------------

  ScanState get state => _state;
  ScannedStudentInfo? get lastResult => _lastResult;
  String? get lastError => _lastError;
  String? get lastErrorUid => _lastErrorUid;
  bool get nfcAvailable => _nfcAvailable;
  bool get qrPaused => _qrPaused;
  int get presentCount => _presentCount;
  int get totalStudents => _totalStudents;
  int get missingCount => _totalStudents - _presentCount;

  @override
  void dispose() {
    _disposed = true;
    _reader.dispose();
    _audio?.dispose();
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  // ----------------------------------------------------------------
  // Initialisation de la session
  // ----------------------------------------------------------------

  /// Démarre la session de scan : NFC + chargement des compteurs.
  Future<void> startSession(List<OfflineStudent> students) async {
    _totalStudents = students.length;

    // Charger le nombre de présences déjà enregistrées pour ce checkpoint
    final attendances = await LocalDb.instance.getAttendancesByCheckpoint(
      checkpointId,
    );
    // Compter les élèves distincts scannés (pas les doublons)
    final uniqueStudents = attendances.map((a) => a.studentId).toSet();
    _presentCount = uniqueStudents.length;

    // Démarrer le NFC
    _nfcAvailable = await _reader.startNfc(_onScanResult);

    _state = ScanState.idle;
    notifyListeners();
  }

  // ----------------------------------------------------------------
  // Traitement des résultats de scan
  // ----------------------------------------------------------------

  /// Appelé depuis MobileScanner (QR) quand un code est détecté.
  Future<void> onQrDetected(String rawValue) async {
    if (_qrPaused || _state == ScanState.scanning) return;
    _state = ScanState.scanning;
    _qrPaused = true;
    notifyListeners();

    final result = await _reader.processQrCode(rawValue);
    _onScanResult(result);
  }

  void _onScanResult(ScanResult result) {
    if (_disposed) return;

    if (result is ScanSuccess) {
      _handleSuccess(result);
    } else if (result is ScanError) {
      _handleError(result);
    }
  }

  void _handleSuccess(ScanSuccess result) {
    // Mettre à jour les compteurs (seulement si premier scan de cet élève)
    if (!result.isDuplicate) {
      _presentCount++;
    }

    _lastResult = ScannedStudentInfo(
      fullName: result.student.fullName,
      scanMethod: result.scanMethod,
      isDuplicate: result.isDuplicate,
      scanSequence: result.scanSequence,
      scannedAt: DateTime.now(),
    );
    _lastError = null;
    _lastErrorUid = null;
    _state = result.isDuplicate ? ScanState.duplicate : ScanState.success;

    _playSuccessSound(result.isDuplicate);
    notifyListeners();
  }

  void _handleError(ScanError result) {
    _lastError = result.message;
    _lastErrorUid = result.uid;
    _lastResult = null;
    _state = ScanState.error;

    _playErrorSound();
    notifyListeners();
  }

  // ----------------------------------------------------------------
  // Remise à l'état idle (après affichage du résultat)
  // ----------------------------------------------------------------

  /// Remet le scanner en mode attente (après 2s d'affichage du résultat).
  void resumeScanning() {
    _state = ScanState.idle;
    _qrPaused = false;
    _lastResult = null;
    _lastError = null;
    _lastErrorUid = null;
    notifyListeners();
  }

  // ----------------------------------------------------------------
  // Sons
  // ----------------------------------------------------------------

  Future<void> _playSuccessSound(bool isDuplicate) async {
    if (_audio == null) return;
    try {
      if (isDuplicate) {
        // Bip court double pour doublon
        await _audio.play(AssetSource('sounds/beep_warning.mp3'));
      } else {
        await _audio.play(AssetSource('sounds/beep_success.mp3'));
      }
    } catch (_) {
      // Son non disponible (fichiers assets manquants) — mode silencieux
    }
  }

  Future<void> _playErrorSound() async {
    if (_audio == null) return;
    try {
      await _audio.play(AssetSource('sounds/beep_error.mp3'));
    } catch (_) {
      // Mode silencieux si assets manquants
    }
  }
}
