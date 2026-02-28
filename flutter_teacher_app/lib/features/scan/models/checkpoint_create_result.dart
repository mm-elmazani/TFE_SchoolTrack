/// Résultat retourné par l'API lors de la création d'un checkpoint (US 2.5).
/// Contient l'ID attribué par le serveur pour la synchronisation future.
library;

/// Réponse du backend après création d'un checkpoint.
class CheckpointCreateResult {
  /// UUID attribué par le serveur (peut différer du UUID client local).
  final String serverId;

  /// Numéro de séquence calculé par le backend.
  final int sequenceOrder;

  const CheckpointCreateResult({
    required this.serverId,
    required this.sequenceOrder,
  });
}
