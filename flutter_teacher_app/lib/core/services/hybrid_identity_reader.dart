/// Service de lecture hybride QR + NFC (US 2.2).
///
/// Combine le scan QR (mobile_scanner) et la lecture NFC (nfc_manager)
/// pour résoudre un UID en élève via la table `students` SQLite locale.
library;

import 'dart:async';
import 'package:flutter/services.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_android.dart';
import 'package:uuid/uuid.dart';
import '../database/local_db.dart';
import '../../features/trips/models/offline_bundle.dart';
import '../../features/scan/models/attendance_record.dart';

const _uuid = Uuid();

/// Résultat d'un scan (succès ou erreur).
sealed class ScanResult {}

/// Scan réussi : élève identifié.
class ScanSuccess extends ScanResult {
  final OfflineStudent student;
  final String scanMethod;   // ScanMethod.*
  final bool isDuplicate;    // true = déjà scanné à ce checkpoint
  final int scanSequence;

  ScanSuccess({
    required this.student,
    required this.scanMethod,
    required this.isDuplicate,
    required this.scanSequence,
  });
}

/// Scan échoué : UID lu mais non assigné, ou erreur de lecture.
class ScanError extends ScanResult {
  final String message;
  final String? uid; // UID brut si disponible (pour debug)

  ScanError({required this.message, this.uid});
}

/// Service gérant la lecture hybride NFC + QR.
/// À instancier une fois par session de scan, à disposer quand on quitte l'écran.
class HybridIdentityReader {
  final String tripId;
  final String checkpointId;

  HybridIdentityReader({required this.tripId, required this.checkpointId});

  bool _nfcStarted = false;

  // ----------------------------------------------------------------
  // NFC
  // ----------------------------------------------------------------

  /// Démarre l'écoute NFC en arrière-plan.
  /// Appelle [onResult] à chaque lecture NFC.
  /// Retourne false si le NFC n'est pas disponible sur l'appareil.
  Future<bool> startNfc(void Function(ScanResult) onResult) async {
    final availability = await NfcManager.instance.checkAvailability();
    if (availability != NfcAvailability.enabled) return false;

    _nfcStarted = true;
    NfcManager.instance.startSession(
      // Polling ISO 14443 couvre les bracelets NTAG213 (NFC-A)
      pollingOptions: {NfcPollingOption.iso14443, NfcPollingOption.iso15693},
      onDiscovered: (NfcTag tag) async {
        final uid = _extractNfcUid(tag);
        if (uid == null) {
          onResult(ScanError(message: 'Impossible de lire le badge NFC.'));
          return;
        }
        final result = await _resolveAndRecord(uid, ScanMethod.nfcPhysical);
        onResult(result);
      },
    );
    return true;
  }

  /// Arrête la session NFC.
  Future<void> stopNfc() async {
    if (_nfcStarted) {
      await NfcManager.instance.stopSession();
      _nfcStarted = false;
    }
  }

  /// Extrait l'UID d'un tag NFC NTAG213 sous forme hexadécimale.
  /// Utilise NfcTagAndroid.id (API nfc_manager 4.x Android).
  String? _extractNfcUid(NfcTag tag) {
    try {
      // NfcTagAndroid.id contient l'UID brut du tag (Uint8List)
      final androidTag = NfcTagAndroid.from(tag);
      if (androidTag != null) {
        return androidTag.id
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join(':')
            .toUpperCase();
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // ----------------------------------------------------------------
  // QR Code (appelé depuis mobile_scanner)
  // ----------------------------------------------------------------

  /// Traite un QR code scanné depuis la caméra.
  /// Le [rawValue] est la valeur brute du QR (UID du token).
  /// Retourne le résultat de la résolution.
  Future<ScanResult> processQrCode(String rawValue) async {
    final uid = rawValue.trim();
    if (uid.isEmpty) {
      return ScanError(message: 'QR code vide ou illisible.');
    }

    // Détecter si QR digital (email) ou QR physique (gravé sur bracelet).
    // Convention : les QR digitaux commencent par "QRD-", les physiques par "QRP-"
    // Si pas de préfixe, on considère QR physique par défaut.
    final method = uid.startsWith('QRD-')
        ? ScanMethod.qrDigital
        : ScanMethod.qrPhysical;

    // Normaliser l'UID (enlever préfixe si présent)
    final normalizedUid = uid.startsWith('QRD-') || uid.startsWith('QRP-')
        ? uid.substring(4)
        : uid;

    return _resolveAndRecord(normalizedUid, method);
  }

  // ----------------------------------------------------------------
  // Résolution UID → étudiant + enregistrement présence
  // ----------------------------------------------------------------

  Future<ScanResult> _resolveAndRecord(String uid, String method) async {
    // 1. Résoudre l'UID en élève via SQLite
    final student = await LocalDb.instance.resolveUid(uid, tripId);
    if (student == null) {
      return ScanError(
        message: 'Badge non reconnu. L\'élève n\'est pas assigné à ce voyage.',
        uid: uid,
      );
    }

    // 2. Vérifier les doublons (même élève, même checkpoint)
    final previousCount = await LocalDb.instance.countAttendances(
      checkpointId,
      student.id,
    );
    final isDuplicate = previousCount > 0;

    // 3. Enregistrer la présence dans SQLite
    final record = AttendanceRecord(
      id: _generateClientUuid(),
      tripId: tripId,
      checkpointId: checkpointId,
      studentId: student.id,
      scannedAt: DateTime.now(),
      scanMethod: method,
      scanSequence: previousCount + 1,
      isManual: false,
    );

    final sequence = await LocalDb.instance.saveAttendance(record);

    // 4. Vibration haptique
    await _triggerHaptic(isDuplicate);

    return ScanSuccess(
      student: student,
      scanMethod: method,
      isDuplicate: isDuplicate,
      scanSequence: sequence,
    );
  }

  // ----------------------------------------------------------------
  // Utilitaires
  // ----------------------------------------------------------------

  /// Génère un UUID v4 côté client (idempotence sync backend).
  String _generateClientUuid() => _uuid.v4();

  Future<void> _triggerHaptic(bool isWarning) async {
    try {
      if (isWarning) {
        await HapticFeedback.mediumImpact();
      } else {
        await HapticFeedback.lightImpact();
      }
    } catch (_) {
      // Haptic non disponible sur certains appareils
    }
  }

  /// Libère les ressources NFC.
  Future<void> dispose() async {
    await stopNfc();
  }
}
