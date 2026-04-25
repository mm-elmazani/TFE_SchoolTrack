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
  if (typeof detail === 'string') return detail;
  if (Array.isArray(detail) && detail.length > 0) {
    return detail[0]?.msg ?? fallback;
  }
  return fallback;
}