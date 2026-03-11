/// Provider pour l'encodage NFC des bracelets (US 1.4).
///
/// Gere le workflow :
/// 1. Generation de l'UID en serie (ST-001, ST-002, ...)
/// 2. Ecriture NDEF sur le bracelet via nfc_manager
/// 3. Enregistrement du token dans le backend via POST /tokens/init
/// 4. Feedback visuel + sonore
library;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:nfc_manager/ndef_record.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_android.dart';

import '../../../core/api/api_client.dart';

/// Etats possibles de l'ecran d'encodage.
enum EncodingState {
  idle,           // En attente (pas de session NFC)
  waitingForTag,  // Session NFC active, en attente d'un tag
  writing,        // Ecriture NDEF en cours
  registering,    // Appel API en cours
  success,        // Encodage reussi
  error,          // Erreur
}

/// Resultat d'un encodage.
class EncodingResult {
  final String tokenUid;
  final String? hardwareUid;
  final bool locked;

  EncodingResult({
    required this.tokenUid,
    this.hardwareUid,
    this.locked = false,
  });
}

class NfcEncodingProvider extends ChangeNotifier {
  final ApiClient _api;
  final AudioPlayer _audioPlayer = AudioPlayer();

  NfcEncodingProvider({ApiClient? api}) : _api = api ?? ApiClient();

  EncodingState _state = EncodingState.idle;
  String? _errorMessage;
  bool _nfcAvailable = false;
  bool _lockTag = false;

  // Compteur pour la generation d'UIDs en serie
  int _nextSequence = 1;
  String _prefix = 'ST';

  // Historique des tokens encodes pendant cette session
  final List<EncodingResult> _encodedTokens = [];

  // Statistiques du stock (depuis l'API)
  Map<String, dynamic>? _stats;

  // Getters
  EncodingState get state => _state;
  String? get errorMessage => _errorMessage;
  bool get nfcAvailable => _nfcAvailable;
  bool get lockTag => _lockTag;
  int get nextSequence => _nextSequence;
  String get prefix => _prefix;
  String get nextTokenUid => '$_prefix-${_nextSequence.toString().padLeft(3, '0')}';
  List<EncodingResult> get encodedTokens => List.unmodifiable(_encodedTokens);
  int get encodedCount => _encodedTokens.length;
  Map<String, dynamic>? get stats => _stats;

  set lockTag(bool value) {
    _lockTag = value;
    notifyListeners();
  }

  set prefix(String value) {
    _prefix = value.toUpperCase();
    notifyListeners();
  }

  set nextSequence(int value) {
    if (value > 0) {
      _nextSequence = value;
      notifyListeners();
    }
  }

  /// Verifie la disponibilite NFC au demarrage.
  Future<void> init() async {
    try {
      final availability = await NfcManager.instance.checkAvailability();
      _nfcAvailable = availability == NfcAvailability.enabled;
    } catch (_) {
      _nfcAvailable = false;
    }
    await loadStats();
    notifyListeners();
  }

  /// Charge les statistiques du stock depuis l'API.
  Future<void> loadStats() async {
    try {
      _stats = await _api.getTokenStats();
    } catch (_) {
      // Pas critique, on continue
    }
    notifyListeners();
  }

  /// Demarre la session NFC et attend un tag.
  /// Quand un tag est detecte, ecrit l'UID NDEF et l'enregistre via l'API.
  Future<void> startEncoding() async {
    if (!_nfcAvailable) {
      _state = EncodingState.error;
      _errorMessage = 'NFC non disponible sur cet appareil.';
      notifyListeners();
      return;
    }

    _state = EncodingState.waitingForTag;
    _errorMessage = null;
    notifyListeners();

    await NfcManager.instance.startSession(
      pollingOptions: {NfcPollingOption.iso14443},
      onDiscovered: (NfcTag tag) async {
        await _handleTagDiscovered(tag);
      },
    );
  }

  /// Arrete la session NFC.
  Future<void> stopEncoding() async {
    try {
      await NfcManager.instance.stopSession();
    } catch (_) {}
    _state = EncodingState.idle;
    notifyListeners();
  }

  /// Gere la decouverte d'un tag NFC.
  Future<void> _handleTagDiscovered(NfcTag tag) async {
    final tokenUid = nextTokenUid;

    // 1. Extraire le UID hardware
    final hardwareUid = _extractHardwareUid(tag);

    // 2. Ecrire l'UID NDEF sur le tag
    _state = EncodingState.writing;
    notifyListeners();

    try {
      final ndef = NdefAndroid.from(tag);
      if (ndef == null || !ndef.isWritable) {
        _state = EncodingState.error;
        _errorMessage = 'Ce tag NFC n\'est pas inscriptible (NDEF).';
        await _playErrorSound();
        notifyListeners();
        return;
      }

      // Construire le message NDEF avec le token_uid comme text record
      final ndefMessage = NdefMessage(records: [
        _createTextRecord(tokenUid),
      ]);

      await ndef.writeNdefMessage(ndefMessage);

      // 3. Verrouillage optionnel (makeReadOnly)
      bool locked = false;
      if (_lockTag) {
        try {
          await ndef.makeReadOnly();
          locked = true;
        } catch (_) {
          // Le verrouillage a echoue, mais l'ecriture a reussi
        }
      }

      // 4. Enregistrer le token dans le backend
      _state = EncodingState.registering;
      notifyListeners();

      await _api.initToken(
        tokenUid: tokenUid,
        tokenType: 'NFC_PHYSICAL',
        hardwareUid: hardwareUid,
      );

      // 5. Succes !
      _encodedTokens.add(EncodingResult(
        tokenUid: tokenUid,
        hardwareUid: hardwareUid,
        locked: locked,
      ));
      _nextSequence++;
      _state = EncodingState.success;
      await _playSuccessSound();
      await HapticFeedback.lightImpact();
      notifyListeners();

      // Rafraichir les stats
      await loadStats();

      // Redemarrer la session pour le prochain tag apres un court delai
      await Future.delayed(const Duration(seconds: 2));
      if (_state == EncodingState.success) {
        _state = EncodingState.waitingForTag;
        notifyListeners();
      }
    } on ApiException catch (e) {
      _state = EncodingState.error;
      _errorMessage = 'Erreur API : ${e.message}';
      await _playErrorSound();
      notifyListeners();
    } catch (e) {
      _state = EncodingState.error;
      _errorMessage = 'Erreur d\'ecriture NFC : $e';
      await _playErrorSound();
      notifyListeners();
    }
  }

  /// Cree un NdefRecord de type TEXT contenant le token_uid.
  /// Format NFC Forum Text Record (TNF=Well-Known, RTD=T).
  NdefRecord _createTextRecord(String text) {
    // Langue "en"
    const languageCode = 'en';
    final languageBytes = Uint8List.fromList(languageCode.codeUnits);
    final textBytes = Uint8List.fromList(text.codeUnits);

    // Payload : [status byte (longueur du code langue)] + [langue] + [texte]
    final payload = Uint8List(1 + languageBytes.length + textBytes.length);
    payload[0] = languageBytes.length; // Status byte (UTF-8, pas de BOM)
    payload.setRange(1, 1 + languageBytes.length, languageBytes);
    payload.setRange(1 + languageBytes.length, payload.length, textBytes);

    return NdefRecord(
      typeNameFormat: TypeNameFormat.wellKnown,
      type: Uint8List.fromList([0x54]), // 'T' = Text record
      identifier: Uint8List(0),
      payload: payload,
    );
  }

  /// Extrait le UID hardware du tag NFC (hex).
  String? _extractHardwareUid(NfcTag tag) {
    try {
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

  Future<void> _playSuccessSound() async {
    try {
      await _audioPlayer.play(AssetSource('sounds/beep_success.mp3'));
    } catch (_) {}
  }

  Future<void> _playErrorSound() async {
    try {
      await _audioPlayer.play(AssetSource('sounds/beep_error.mp3'));
    } catch (_) {}
  }

  /// Remet l'etat a idle apres une erreur.
  void clearError() {
    _state = EncodingState.idle;
    _errorMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    try {
      NfcManager.instance.stopSession();
    } catch (_) {}
    super.dispose();
  }
}
