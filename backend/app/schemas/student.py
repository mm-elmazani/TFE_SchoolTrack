"""
Schémas Pydantic pour les élèves.
"""

import uuid
from datetime import datetime
from typing import List, Optional
from pydantic import BaseModel, EmailStr, field_validator, model_validator


class StudentCreate(BaseModel):
    """Schéma de création manuelle d'un élève (POST /students).

    Si `class_id` est fourni, l'élève est immédiatement assigné à cette classe
    et ajouté aux voyages PLANNED/ACTIVE liés a cette classe.
    """
    first_name: str
    last_name: str
    email: Optional[EmailStr] = None
    phone: Optional[str] = None
    class_id: Optional[uuid.UUID] = None

    @field_validator("first_name", "last_name")
    @classmethod
    def not_empty(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("Le champ ne peut pas être vide.")
        return v.strip()


class StudentUpdate(BaseModel):
    first_name: Optional[str] = None
    last_name: Optional[str] = None
    email: Optional[EmailStr] = None
    phone: Optional[str] = None

    @field_validator("first_name", "last_name")
    @classmethod
    def not_empty(cls, v: Optional[str]) -> Optional[str]:
        if v is not None and not v.strip():
            raise ValueError("Le champ ne peut pas être vide.")
        return v.strip() if v else v


class StudentResponse(BaseModel):
    id: uuid.UUID
    school_id: uuid.UUID
    first_name: str
    last_name: str
    email: Optional[str]
    phone: Optional[str] = None
    photo_url: Optional[str] = None
    is_deleted: bool = False
    created_at: datetime

    model_config = {"from_attributes": True}

    @model_validator(mode="before")
    @classmethod
    def default_is_deleted(cls, data):
        if hasattr(data, "is_deleted") and data.is_deleted is None:
            data.is_deleted = False
        elif isinstance(data, dict) and data.get("is_deleted") is None:
            data["is_deleted"] = False
        return data


class StudentImportRow(BaseModel):
    first_name: str
    last_name: str
    email: Optional[str] = None
    phone: Optional[str] = None
    classe: Optional[str] = None  # nom de la classe (optionnel, colonne CSV)


class ImportError(BaseModel):
    row: int
    content: str
    reason: str


class StudentImportReport(BaseModel):
    total_rows: int
    inserted: int
    rejected: int
    duplicates_in_file: int
    duplicates_in_db: int
    errors: List[ImportError]


# --- RGPD US 6.5 — Export des donnees personnelles ---

class StudentGdprExport(BaseModel):
    exported_at: str
    student: dict
    classes: List[dict]
    trips: List[dict]
    attendances: List[dict]
    assignments: List[dict]
    alerts: List[dict]
