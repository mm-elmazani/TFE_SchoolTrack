// Constantes globales de l'application

/// URL de base de l'API FastAPI.
/// En développement local, pointe vers l'instance FastAPI sur le port 8001.
/// En production, Traefik route via le domaine configuré.
const String kApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:8000',
);

/// Taille maximale acceptée pour un fichier CSV (5 Mo)
const int kMaxCsvSizeBytes = 5 * 1024 * 1024;

/// Extensions de fichier acceptées pour l'import
const List<String> kAllowedCsvExtensions = ['csv'];
