/// Constantes globales de l'application SchoolTrack (enseignants).
library;

/// URL de base de l'API FastAPI.
/// En dev : adresse IP locale de la machine qui fait tourner le backend.
/// En prod : URL publique via Traefik (ex: https://api.schooltrack.be).
const String kApiBaseUrl = 'http://10.0.2.2:8000';

/// Durée de validité du cache offline (7 jours en millisecondes).
const int kOfflineCacheDurationMs = 7 * 24 * 60 * 60 * 1000;
