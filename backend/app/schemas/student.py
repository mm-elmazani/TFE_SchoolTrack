"""
Schémas Pydantic pour les élèves.
"""

import uuid
from datetime import datetime
from typing import List, Optional
from pydantic import BaseModel, EmailStr, field_validator, model_validator


class StudentCreate(BaseModel):
    """Schéma de création manuelle d'un élève (POST /students)."""
    first_name: str
    last_name: str
    email: Optional[EmailStr] = None

    @field_validator("first_name", "last_name")
    @classmethod
    def not_empty(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("Le champ ne peut pas être vide.")
        return v.strip()


class StudentUpdate(BaseModel):
    """Schéma de mise à jour d'un élève (PUT /students/{id})."""
    first_name: Optional[str] = None
    last_name: Optional[str] = None
    email: Optional[EmailStr] = None

    @field_validator("first_name", "last_name")
    @classmethod
    def not_empty(cls, v: Optional[str]) -> Optional[str]:
        if v is not None and not v.strip():
            raise ValueError("Le champ ne peut pas être vide.")
        return v.strip() if v else v


class StudentResponse(BaseModel):
    """Schéma de réponse pour un élève (GET /students)."""
    id: uuid.UUID
    first_name: str
    last_name: str
    email: Optional[str]
    is_deleted: bool = False
    created_at: datetime

    model_config = {"from_attributes": True}

    @model_validator(mode="before")
    @classmethod
    def default_is_deleted(cls, data):
        """Garantit is_deleted=False si None (mock tests / anciens enregistrements)."""
        if hasattr(data, "is_deleted") and data.is_deleted is None:
            data.is_deleted = False
        elif isinstance(data, dict) and data.get("is_deleted") is None:
            data["is_deleted"] = False
        return data


class StudentImportRow(BaseModel):
    """Représente une ligne valide du CSV après parsing."""
    first_name: str
    last_name: str
    email: Optional[str] = None
    classe: Optional[str] = None  # nom de la classe (optionnel, colonne CSV)


class ImportError(BaseModel):
    """Détail d'une ligne rejetée lors de l'import."""
    row: int
    content: str
    reason: str


class StudentImportReport(BaseModel):
    """Rapport retourné après un import CSV."""
    total_rows: int
    inserted: int
    rejected: int
    duplicates_in_file: int
    duplicates_in_db: int
    errors: List[ImportError]


# --- RGPD US 6.5 — Export des donnees personnelles ---

class StudentGdprExport(BaseModel):
    """Export complet des donnees personnelles d'un eleve (RGPD droit d'acces)."""
    exported_at: str
    student: dict
    classes: List[dict]
    trips: List[dict]
    attendances: List[dict]
    assignments: List[dict]
    alerts: List[dict]
