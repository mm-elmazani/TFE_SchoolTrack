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
