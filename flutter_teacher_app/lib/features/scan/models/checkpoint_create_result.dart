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
