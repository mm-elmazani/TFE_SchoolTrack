"""
Schémas Pydantic pour les checkpoints (US 2.5).
Création sur le terrain par un enseignant via l'app mobile.
"""

import uuid
from datetime import datetime
from typing import Optional

from pydantic import BaseModel, field_validator


class CheckpointCreate(BaseModel):
    """Données nécessaires pour créer un checkpoint sur le terrain."""
    name: str
    description: Optional[str] = None

    @field_validator("name")
    @classmethod
    def name_not_empty(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("Le nom du checkpoint ne peut pas être vide.")
        return v.strip()


class CheckpointResponse(BaseModel):
    """Réponse renvoyée après création ou lecture d'un checkpoint."""
    id: uuid.UUID
    trip_id: uuid.UUID
    name: str
    description: Optional[str]
    sequence_order: int
    status: str
    created_at: datetime

    model_config = {"from_attributes": True}


# ---------------------------------------------------------------------------
# US 4.4 — Timeline et resume checkpoints
# ---------------------------------------------------------------------------


class CheckpointTimelineEntry(BaseModel):
    """Un checkpoint dans la timeline avec ses statistiques de scan."""
    id: uuid.UUID
    name: str
    description: Optional[str] = None
    sequence_order: int
    status: str
    created_at: Optional[datetime] = None
    started_at: Optional[datetime] = None
    closed_at: Optional[datetime] = None
    created_by_name: Optional[str] = None
    scan_count: int = 0
    student_count: int = 0
    duration_minutes: Optional[int] = None


class CheckpointsSummary(BaseModel):
    """Resume des checkpoints d'un voyage pour la direction."""
    trip_id: uuid.UUID
    trip_destination: str
    total_checkpoints: int
    active_checkpoints: int
    closed_checkpoints: int
    total_scans: int
    avg_duration_minutes: Optional[float] = None
    timeline: list[CheckpointTimelineEntry] = []
