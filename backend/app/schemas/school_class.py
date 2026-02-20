"""
Schémas Pydantic pour les classes scolaires (US 1.3).
"""

import uuid
from datetime import datetime
from typing import List, Optional

from pydantic import BaseModel, field_validator


class ClassCreate(BaseModel):
    name: str
    year: Optional[str] = None

    @field_validator("name")
    @classmethod
    def name_not_empty(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("Le nom de la classe ne peut pas être vide.")
        return v.strip()


class ClassUpdate(BaseModel):
    name: Optional[str] = None
    year: Optional[str] = None

    @field_validator("name")
    @classmethod
    def name_not_empty(cls, v: Optional[str]) -> Optional[str]:
        if v is not None and not v.strip():
            raise ValueError("Le nom de la classe ne peut pas être vide.")
        return v.strip() if v else v


class ClassResponse(BaseModel):
    id: uuid.UUID
    name: str
    year: Optional[str]
    nb_students: int
    nb_teachers: int
    created_at: datetime
    updated_at: datetime

    model_config = {"from_attributes": True}


class ClassStudentsAssign(BaseModel):
    """Corps de requête pour assigner des élèves à une classe."""
    student_ids: List[uuid.UUID]

    @field_validator("student_ids")
    @classmethod
    def not_empty(cls, v: List[uuid.UUID]) -> List[uuid.UUID]:
        if not v:
            raise ValueError("La liste d'élèves ne peut pas être vide.")
        return v


class ClassTeachersAssign(BaseModel):
    """Corps de requête pour assigner des enseignants à une classe."""
    teacher_ids: List[uuid.UUID]

    @field_validator("teacher_ids")
    @classmethod
    def not_empty(cls, v: List[uuid.UUID]) -> List[uuid.UUID]:
        if not v:
            raise ValueError("La liste d'enseignants ne peut pas être vide.")
        return v
