/// Provider gérant l'état de la session de scan (US 2.2 + US 2.3 + US 2.4).
library;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../../../core/database/local_db.dart';
import '../../../core/services/hybrid_identity_reader.dart';
import '../../../features/scan/models/attendance_record.dart';
import '../../../features/trips/models/offline_bundle.dart';

const _uuid = Uuid();

/// État de l'écran de scan.
enum ScanState { idle, scanning, success, duplicate, error }

/// Informations du dernier scan réussi d'un élève (US 2.3 — liste temps réel).
class StudentScanInfo {
  final String scanMethod;
  final DateTime scannedAt;

  const StudentScanInfo({required this.scanMethod, required this.scannedAt});
}

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

  // US 2.3 — suivi temps réel par élève
  List<OfflineStudent> _students = [];
  final Map<String, StudentScanInfo> _presentMap = {};

  // US 2.5 — statut du checkpoint courant (DRAFT→ACTIVE au 1er scan)
  String _checkpointStatus = 'ACTIVE'; // défaut sécurisé

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
  String get checkpointStatus => _checkpointStatus;

  // US 2.3 — listes temps réel
  /// Élèves déjà scannés, triés par heure de scan DESC (plus récent en premier).
  List<OfflineStudent> get presentStudents {
    final list = _students.where((s) => _presentMap.containsKey(s.id)).toList();
    list.sort((a, b) =>
        _presentMap[b.id]!.scannedAt.compareTo(_presentMap[a.id]!.scannedAt));
    return list;
  }

  /// Élèves non encore scannés, triés par nom ASC.
  List<OfflineStudent> get missingStudents =>
      _students.where((s) => !_presentMap.containsKey(s.id)).toList();

  /// Informations du scan d'un élève donné (null si non scanné).
  StudentScanInfo? scanInfoOf(String studentId) => _presentMap[studentId];

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
    _students = List.unmodifiable(students);
    _totalStudents = students.length;

    // Charger le statut du checkpoint pour la transition DRAFT→ACTIVE (US 2.5)
    final checkpoint = await LocalDb.instance.getCheckpointById(checkpointId);
    if (checkpoint != null) _checkpointStatus = checkpoint.status;

    // Charger les présences déjà enregistrées pour ce checkpoint
    final attendances = await LocalDb.instance.getAttendancesByCheckpoint(
      checkpointId,
    );
    // Triées ASC → putIfAbsent garde le premier scan (le plus ancien)
    for (final att in attendances) {
      _presentMap.putIfAbsent(
        att.studentId,
        () => StudentScanInfo(
          scanMethod: att.scanMethod,
          scannedAt: att.scannedAt,
        ),
      );
    }
    _presentCount = _presentMap.length;

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
    // Mettre à jour les compteurs et la map (seulement si premier scan)
    if (!result.isDuplicate) {
      _presentCount++;
      _presentMap[result.student.id] = StudentScanInfo(
        scanMethod: result.scanMethod,
        scannedAt: DateTime.now(),
      );

      // Transition DRAFT→ACTIVE au premier scan réussi (US 2.5)
      if (_checkpointStatus == 'DRAFT') {
        _checkpointStatus = 'ACTIVE';
        LocalDb.instance.activateCheckpoint(checkpointId);
      }
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

  // ----------------------------------------------------------------
  // Marquage manuel (US 2.4)
  // ----------------------------------------------------------------

  /// Codes de justification pour un marquage manuel.
  static const List<(String, String)> justificationOptions = [
    ('BADGE_MISSING', 'Badge / bracelet manquant'),
    ('BADGE_DAMAGED', 'Badge / bracelet endommagé'),
    ('SCANNER_FAILURE', 'Scanner défaillant'),
    ('TEACHER_CONFIRMATION', 'Présence confirmée par l\'enseignant'),
    ('OTHER', 'Autre'),
  ];

  /// Marque manuellement un élève comme présent avec une justification (US 2.4).
  ///
  /// Enregistre la présence en SQLite (is_manual=1, scan_method='MANUAL')
  /// et met à jour la liste temps réel. Si l'élève est déjà présent,
  /// l'enregistrement est sauvegardé (historique) mais le compteur ne change pas.
  Future<void> markManually({
    required OfflineStudent student,
    required String justification,
    String? comment,
  }) async {
    if (_disposed) return;

    final now = DateTime.now();
    final record = AttendanceRecord(
      id: _uuid.v4(),
      tripId: tripId,
      checkpointId: checkpointId,
      studentId: student.id,
      scannedAt: now,
      scanMethod: ScanMethod.manual,
      isManual: true,
      justification: justification,
      comment: comment,
    );

    await LocalDb.instance.saveAttendance(record);

    // Mise à jour de la map seulement si l'élève n'était pas encore présent
    if (!_presentMap.containsKey(student.id)) {
      _presentCount++;
      _presentMap[student.id] = StudentScanInfo(
        scanMethod: ScanMethod.manual,
        scannedAt: now,
      );

      // Transition DRAFT→ACTIVE au premier marquage (US 2.5)
      if (_checkpointStatus == 'DRAFT') {
        _checkpointStatus = 'ACTIVE';
        LocalDb.instance.activateCheckpoint(checkpointId);
      }
    }

    notifyListeners();
  }

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
