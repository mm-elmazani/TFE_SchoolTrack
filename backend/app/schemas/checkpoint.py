"""
Schémas Pydantic pour les checkpoints.
Création sur le terrain par un enseignant via l'app mobile.
"""

import uuid
from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field, field_validator

# Limite alignee avec le frontend mobile et web pour eviter de saturer l'UI.
DESCRIPTION_MAX_LENGTH = 500


class CheckpointCreate(BaseModel):
    name: str
    description: Optional[str] = Field(default=None, max_length=DESCRIPTION_MAX_LENGTH)
    id: Optional[uuid.UUID] = None  # UUID client pour sync offline

    @field_validator("name")
    @classmethod
    def name_not_empty(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("Le nom du checkpoint ne peut pas être vide.")
        return v.strip()


class CheckpointUpdate(BaseModel):
    name: str
    description: Optional[str] = Field(default=None, max_length=DESCRIPTION_MAX_LENGTH)

    @field_validator("name")
    @classmethod
    def name_not_empty(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("Le nom du checkpoint ne peut pas être vide.")
        return v.strip()


class CheckpointResponse(BaseModel):
    id: uuid.UUID
    trip_id: uuid.UUID
    name: str
    description: Optional[str]
    sequence_order: int
    status: str
    created_at: datetime

    model_config = {"from_attributes": True}


class CheckpointTimelineEntry(BaseModel):
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
    trip_id: uuid.UUID
    trip_destination: str
    total_checkpoints: int
    active_checkpoints: int
    closed_checkpoints: int
    total_scans: int
    avg_duration_minutes: Optional[float] = None
    timeline: list[CheckpointTimelineEntry] = []
