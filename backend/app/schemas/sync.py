"""
Schémas Pydantic pour la synchronisation offline → online (US 3.1 + US 3.2).
Endpoint : POST /api/sync/attendances
"""

import uuid
from datetime import datetime
from typing import List, Optional

from pydantic import BaseModel, field_validator

VALID_SCAN_METHODS = {"NFC_PHYSICAL", "QR_PHYSICAL", "QR_DIGITAL", "MANUAL"}
MAX_BATCH_SIZE = 500


class ScanItem(BaseModel):
    """Un scan de présence généré côté client (Flutter) en mode offline."""

    client_uuid: uuid.UUID        # UUID généré par Flutter (package uuid) — clé d'idempotence
    student_id: uuid.UUID
    checkpoint_id: uuid.UUID
    trip_id: uuid.UUID
    scanned_at: datetime          # Timestamp local au moment du scan (avant réseau)
    scan_method: str              # NFC_PHYSICAL, QR_PHYSICAL, QR_DIGITAL, MANUAL
    scan_sequence: int = 1        # Numéro de scan au checkpoint (US 2.6 : 1=premier, 2+=doublon)
    is_manual: bool = False       # True si marquage manuel (US 2.4)
    justification: Optional[str] = None  # Raison du marquage manuel (BADGE_MISSING, etc.)
    comment: Optional[str] = None        # Commentaire libre optionnel

    @field_validator("scan_method")
    @classmethod
    def valid_scan_method(cls, v: str) -> str:
        if v not in VALID_SCAN_METHODS:
            raise ValueError(f"Méthode de scan invalide. Valeurs acceptées : {VALID_SCAN_METHODS}")
        return v


class SyncRequest(BaseModel):
    """Corps de la requête batch de synchronisation."""

    scans: List[ScanItem]
    device_id: str = ""           # Identifiant de l'appareil Flutter (pour sync_logs)

    @field_validator("scans")
    @classmethod
    def scans_not_too_large(cls, v: List[ScanItem]) -> List[ScanItem]:
        if len(v) > MAX_BATCH_SIZE:
            raise ValueError(f"Batch trop grand : maximum {MAX_BATCH_SIZE} scans par requête.")
        return v


class TemporalAnomaly(BaseModel):
    """Incohérence temporelle détectée entre deux checkpoints pour un même élève (US 3.2)."""

    student_id: str
    trip_id: str
    checkpoint_before: str        # Nom du checkpoint d'ordre inférieur
    checkpoint_after: str         # Nom du checkpoint d'ordre supérieur
    scanned_at_before: str        # ISO 8601
    scanned_at_after: str         # ISO 8601 — scanné AVANT checkpoint_before
    description: str              # Message lisible (pour le dashboard)


class SyncResponse(BaseModel):
    """Rapport de synchronisation retourné par le serveur (US 3.1 + US 3.2)."""

    # US 3.1 — idempotence
    accepted: List[str]           # client_uuids insérés comme nouveaux canoniques
    duplicate: List[str]          # client_uuids déjà connus (idempotence)
    total_received: int
    total_inserted: int

    # US 3.2 — fusion multi-enseignants
    merged: List[str] = []        # client_uuids dont le scan (plus ancien) a remplacé le canonique
    temporal_anomalies: List[TemporalAnomaly] = []  # incohérences d'ordre entre checkpoints
    total_merged: int = 0
