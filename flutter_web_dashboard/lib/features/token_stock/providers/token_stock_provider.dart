// Provider pour le suivi du stock de bracelets (US 1.4).
import 'package:flutter/foundation.dart';

import '../../../core/api/api_client.dart';

enum TokenStockState { idle, loading, ready, error }

/// Token du stock tel que retourne par l'API.
class StockToken {
  final int id;
  final String tokenUid;
  final String tokenType;
  final String status;
  final String? hardwareUid;
  final DateTime createdAt;
  final DateTime? lastAssignedAt;

  StockToken({
    required this.id,
    required this.tokenUid,
    required this.tokenType,
    required this.status,
    this.hardwareUid,
    required this.createdAt,
    this.lastAssignedAt,
  });

  factory StockToken.fromJson(Map<String, dynamic> json) {
    return StockToken(
      id: json['id'] as int,
      tokenUid: json['token_uid'] as String,
      tokenType: json['token_type'] as String,
      status: json['status'] as String,
      hardwareUid: json['hardware_uid'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      lastAssignedAt: json['last_assigned_at'] != null
          ? DateTime.parse(json['last_assigned_at'] as String)
          : null,
    );
  }
}

class TokenStockProvider extends ChangeNotifier {
  final ApiClient _api = ApiClient();

  TokenStockState _state = TokenStockState.idle;
  String? _errorMessage;
  List<StockToken> _tokens = [];
  Map<String, dynamic>? _stats;

  // Filtres
  String? _filterStatus;
  String? _filterType;

  // Getters
  TokenStockState get state => _state;
  String? get errorMessage => _errorMessage;
  List<StockToken> get tokens => _tokens;
  Map<String, dynamic>? get stats => _stats;
  String? get filterStatus => _filterStatus;
  String? get filterType => _filterType;

  int get total => _stats?['total'] ?? 0;
  int get available => _stats?['available'] ?? 0;
  int get assigned => _stats?['assigned'] ?? 0;
  int get damaged => _stats?['damaged'] ?? 0;
  int get lost => _stats?['lost'] ?? 0;

  /// Charge les tokens et les stats depuis l'API.
  Future<void> load() async {
    _state = TokenStockState.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      final results = await Future.wait([
        _api.getTokens(status: _filterStatus, tokenType: _filterType),
        _api.getTokenStats(),
      ]);

      _tokens = (results[0] as List<Map<String, dynamic>>)
          .map((j) => StockToken.fromJson(j))
          .toList();
      _stats = results[1] as Map<String, dynamic>;
      _state = TokenStockState.ready;
    } on ApiException catch (e) {
      _state = TokenStockState.error;
      _errorMessage = e.message;
    } catch (e) {
      _state = TokenStockState.error;
      _errorMessage = 'Erreur inattendue : $e';
    }
    notifyListeners();
  }

  /// Applique un filtre par statut et recharge.
  void setFilterStatus(String? status) {
    _filterStatus = status;
    load();
  }

  /// Applique un filtre par type et recharge.
  void setFilterType(String? type) {
    _filterType = type;
    load();
  }

  /// Met a jour le statut d'un token.
  Future<void> updateStatus(int tokenId, String newStatus) async {
    try {
      await _api.updateTokenStatus(tokenId, newStatus);
      await load();
    } on ApiException catch (e) {
      _errorMessage = e.message;
      notifyListeners();
    }
  }

  /// Supprime un token du stock.
  Future<bool> deleteToken(int tokenId) async {
    try {
      await _api.deleteToken(tokenId);
      await load();
      return true;
    } on ApiException catch (e) {
      _errorMessage = e.message;
      notifyListeners();
      return false;
    }
  }
}
