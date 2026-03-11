/// Service de lecture hybride QR + NFC (US 2.2).
///
/// Combine le scan QR (mobile_scanner) et la lecture NFC (nfc_manager)
/// pour résoudre un UID en élève via la table `students` SQLite locale.
library;

import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:nfc_manager/ndef_record.dart';
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
    debugPrint('[NFC] checkAvailability...');
    final availability = await NfcManager.instance.checkAvailability();
    debugPrint('[NFC] availability = $availability');
    if (availability != NfcAvailability.enabled) return false;

    // Stopper toute session NFC residuelle avant d'en demarrer une nouvelle
    try {
      await NfcManager.instance.stopSession();
      debugPrint('[NFC] session precedente stoppee');
    } catch (_) {}

    // Laisser le systeme NFC se reinitialiser (evite conflit avec la camera)
    await Future.delayed(const Duration(milliseconds: 500));

    _nfcStarted = true;
    debugPrint('[NFC] startSession...');
    await NfcManager.instance.startSession(
      // Polling ISO 14443 couvre les bracelets NTAG213 (NFC-A)
      pollingOptions: {NfcPollingOption.iso14443},
      onDiscovered: (NfcTag tag) async {
        debugPrint('[NFC] >>> tag detecte !');
        try {
          // Lire le token_uid depuis le contenu NDEF (ecrit lors de l'encodage US 1.4).
          final tokenUid = await _readNdefTokenUid(tag);
          debugPrint('[NFC] tokenUid lu = $tokenUid');
          if (tokenUid == null) {
            onResult(ScanError(message: 'Bracelet NFC illisible (pas de donnees NDEF).'));
            return;
          }
          final result = await _resolveAndRecord(tokenUid, ScanMethod.nfcPhysical);
          debugPrint('[NFC] resultat: ${result is ScanSuccess ? 'SUCCESS ${(result as ScanSuccess).student.fullName}' : 'ERROR'}');
          onResult(result);
        } catch (e) {
          debugPrint('[NFC] EXCEPTION: $e');
          onResult(ScanError(message: 'Erreur lecture NFC : $e'));
        }
      },
    );
    debugPrint('[NFC] session demarree OK');
    return true;
  }

  /// Arrête la session NFC.
  Future<void> stopNfc() async {
    if (_nfcStarted) {
      await NfcManager.instance.stopSession();
      _nfcStarted = false;
    }
  }

  /// Lit le token_uid depuis le contenu NDEF d'un tag NFC.
  /// Le token_uid est encode comme NFC Forum Text Record lors de l'encodage (US 1.4).
  Future<String?> _readNdefTokenUid(NfcTag tag) async {
    try {
      final ndef = NdefAndroid.from(tag);
      if (ndef == null) return null;

      // Utiliser le message NDEF cache (lu a la decouverte du tag)
      // ou le relire si absent
      final message = ndef.cachedNdefMessage ?? await ndef.getNdefMessage();
      if (message == null || message.records.isEmpty) return null;

      // Chercher le premier Text Record (TNF=Well-Known, RTD=T)
      for (final record in message.records) {
        if (record.typeNameFormat == TypeNameFormat.wellKnown &&
            record.type.length == 1 &&
            record.type[0] == 0x54) {     // RTD 'T' (Text)
          return _decodeTextRecord(record.payload);
        }
      }

      // Fallback : si pas de Text Record, essayer le payload brut du premier record
      if (message.records.first.payload.isNotEmpty) {
        return String.fromCharCodes(message.records.first.payload).trim();
      }

      return null;
    } catch (_) {
      return null;
    }
  }

  /// Decode le payload d'un NFC Forum Text Record.
  /// Format : [status byte] [language code] [text content]
  /// Le status byte contient la longueur du code langue dans les 6 bits de poids faible.
  String? _decodeTextRecord(Uint8List payload) {
    if (payload.isEmpty) return null;
    final langLength = payload[0] & 0x3F; // 6 bits de poids faible
    if (payload.length <= 1 + langLength) return null;
    return String.fromCharCodes(payload.sublist(1 + langLength)).trim();
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

    // QR digital : le token_uid en SQLite INCLUT le préfixe "QRD-" (ex: "QRD-A1B2C3D4")
    //              → ne pas stripper, chercher le token_uid complet.
    // QR physique avec préfixe "QRP-" : le token_uid en DB n'a PAS de préfixe
    //              → stripper "QRP-" avant la recherche.
    // QR physique sans préfixe : token_uid brut tel quel.
    final normalizedUid = uid.startsWith('QRP-') ? uid.substring(4) : uid;

    return _resolveAndRecord(normalizedUid, method);
  }

  // ----------------------------------------------------------------
  // Résolution UID → étudiant + enregistrement présence
  // ----------------------------------------------------------------

  Future<ScanResult> _resolveAndRecord(String uid, String method) async {
    // 1. Résoudre l'UID en élève via SQLite.
    // QR digital (QRD-) : uid = "QRD-XXXXXXXX" → token_uid complet en DB (préfixe inclus)
    // NFC / QR physique  : uid = token_uid nu → token_uid exact en DB
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
