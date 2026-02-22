"""
Schémas Pydantic pour les voyages.
"""

import uuid
from datetime import date, datetime
from typing import List, Optional

from pydantic import BaseModel, field_validator


class ClassSummary(BaseModel):
    """Résumé d'une classe dans un voyage (nom + nb élèves inscrits)."""
    name: str
    student_count: int


class TripCreate(BaseModel):
    destination: str
    date: date
    description: Optional[str] = None
    class_ids: List[uuid.UUID]  # au moins 1 classe obligatoire

    @field_validator("date")
    @classmethod
    def date_must_be_future(cls, v: date) -> date:
        if v <= date.today():
            raise ValueError("La date du voyage doit être dans le futur.")
        return v

    @field_validator("class_ids")
    @classmethod
    def at_least_one_class(cls, v: List[uuid.UUID]) -> List[uuid.UUID]:
        if not v:
            raise ValueError("Au moins une classe doit être sélectionnée.")
        return v

    @field_validator("destination")
    @classmethod
    def destination_not_empty(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("La destination ne peut pas être vide.")
        return v.strip()


class TripUpdate(BaseModel):
    destination: Optional[str] = None
    date: Optional[date] = None
    description: Optional[str] = None
    status: Optional[str] = None

    @field_validator("date")
    @classmethod
    def date_must_be_future(cls, v: Optional[date]) -> Optional[date]:
        if v is not None and v <= date.today():
            raise ValueError("La date du voyage doit être dans le futur.")
        return v

    @field_validator("status")
    @classmethod
    def valid_status(cls, v: Optional[str]) -> Optional[str]:
        allowed = {"PLANNED", "ACTIVE", "COMPLETED", "ARCHIVED"}
        if v is not None and v not in allowed:
            raise ValueError(f"Statut invalide. Valeurs acceptées : {allowed}")
        return v


class TripResponse(BaseModel):
    id: uuid.UUID
    destination: str
    date: date
    description: Optional[str]
    status: str
    total_students: int
    classes: List[ClassSummary] = []
    created_at: datetime
    updated_at: datetime

    model_config = {"from_attributes": True}
