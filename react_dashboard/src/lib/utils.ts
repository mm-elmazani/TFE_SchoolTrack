import { type ClassValue, clsx } from "clsx"
import { twMerge } from "tailwind-merge"

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs))
}

/**
 * Extrait un message d'erreur lisible depuis une réponse API.
 * Gère les deux formats possibles :
 *  - string  : erreur métier FastAPI  { "detail": "Message" }
 *  - array   : erreur validation Pydantic { "detail": [{ "msg": "...", "loc": [...] }] }
 */
export function getApiError(err: any, fallback = 'Une erreur est survenue'): string {
  const detail = err?.response?.data?.detail;
  if (!detail) return fallback;
  // Erreur métier FastAPI : detail est une string
  if (typeof detail === 'string') return detail;
  // Erreur de validation Pydantic : detail est un tableau d'objets techniques
  // On affiche un message générique plutôt que le message Pydantic brut
  if (Array.isArray(detail) && detail.length > 0) return fallback;
  return fallback;
}