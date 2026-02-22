"""
Schémas Pydantic pour les assignations de bracelets (US 1.5).
"""

import uuid
from datetime import datetime
from typing import List, Optional

from pydantic import BaseModel, field_validator

VALID_ASSIGNMENT_TYPES = {"NFC_PHYSICAL", "QR_PHYSICAL", "QR_DIGITAL"}


class AssignmentCreate(BaseModel):
    """Corps de requête pour assigner un bracelet à un élève."""
    token_uid: str
    student_id: uuid.UUID
    trip_id: uuid.UUID
    assignment_type: str  # NFC_PHYSICAL, QR_PHYSICAL, QR_DIGITAL

    @field_validator("token_uid")
    @classmethod
    def token_uid_not_empty(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("L'UID du token ne peut pas être vide.")
        return v.strip().upper()

    @field_validator("assignment_type")
    @classmethod
    def valid_assignment_type(cls, v: str) -> str:
        if v not in VALID_ASSIGNMENT_TYPES:
            raise ValueError(f"Type invalide. Valeurs acceptées : {VALID_ASSIGNMENT_TYPES}")
        return v


class AssignmentReassign(BaseModel):
    """Corps de requête pour réassigner un bracelet (libère l'ancien)."""
    token_uid: str
    student_id: uuid.UUID
    trip_id: uuid.UUID
    assignment_type: str
    justification: str  # Obligatoire pour la réassignation

    @field_validator("token_uid")
    @classmethod
    def token_uid_not_empty(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("L'UID du token ne peut pas être vide.")
        return v.strip().upper()

    @field_validator("assignment_type")
    @classmethod
    def valid_assignment_type(cls, v: str) -> str:
        if v not in VALID_ASSIGNMENT_TYPES:
            raise ValueError(f"Type invalide. Valeurs acceptées : {VALID_ASSIGNMENT_TYPES}")
        return v

    @field_validator("justification")
    @classmethod
    def justification_not_empty(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("Une justification est obligatoire pour la réassignation.")
        return v.strip()


class AssignmentResponse(BaseModel):
    """Réponse après assignation."""
    id: int
    token_uid: str
    student_id: uuid.UUID
    trip_id: uuid.UUID
    assignment_type: str
    assigned_at: datetime
    released_at: Optional[datetime]

    model_config = {"from_attributes": True}


class TripAssignmentStatus(BaseModel):
    """Statut global des assignations pour un voyage."""
    trip_id: uuid.UUID
    total_students: int
    assigned_students: int
    unassigned_students: int
    assignments: List[AssignmentResponse]


class TripStudentWithAssignment(BaseModel):
    """Élève inscrit à un voyage avec son statut d'assignation bracelet."""
    id: uuid.UUID
    first_name: str
    last_name: str
    email: Optional[str]
    token_uid: Optional[str] = None
    assignment_type: Optional[str] = None
    assigned_at: Optional[datetime] = None

    model_config = {"from_attributes": True}


class TripStudentsResponse(BaseModel):
    """Liste complète des élèves d'un voyage avec leur statut d'assignation."""
    trip_id: uuid.UUID
    total: int
    assigned: int
    unassigned: int
    students: List[TripStudentWithAssignment]
