"""
Schemas Pydantic pour les tokens (US 1.4) et assignations de bracelets (US 1.5).
"""

import uuid
from datetime import datetime
from typing import List, Optional

from pydantic import BaseModel, field_validator

VALID_ASSIGNMENT_TYPES = {"NFC_PHYSICAL", "QR_PHYSICAL", "QR_DIGITAL"}
VALID_TOKEN_TYPES = {"NFC_PHYSICAL", "QR_PHYSICAL"}
VALID_TOKEN_STATUSES = {"AVAILABLE", "ASSIGNED", "DAMAGED", "LOST"}


# ----------------------------------------------------------------
# Schemas US 1.4 — Initialisation du stock de bracelets
# ----------------------------------------------------------------


class TokenCreate(BaseModel):
    """Enregistrer un token unique dans le stock."""
    token_uid: str
    token_type: str  # NFC_PHYSICAL, QR_PHYSICAL
    hardware_uid: Optional[str] = None  # UID hardware NFC (hex) lu lors de l'encodage

    @field_validator("token_uid")
    @classmethod
    def token_uid_not_empty(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("L'UID du token ne peut pas etre vide.")
        return v.strip().upper()

    @field_validator("token_type")
    @classmethod
    def valid_token_type(cls, v: str) -> str:
        if v not in VALID_TOKEN_TYPES:
            raise ValueError(f"Type invalide. Valeurs acceptees : {VALID_TOKEN_TYPES}")
        return v


class TokenBatchCreate(BaseModel):
    """Enregistrer un lot de tokens en une seule requete."""
    tokens: List[TokenCreate]

    @field_validator("tokens")
    @classmethod
    def tokens_not_empty(cls, v: List[TokenCreate]) -> List[TokenCreate]:
        if not v:
            raise ValueError("La liste de tokens ne peut pas etre vide.")
        return v


class TokenResponse(BaseModel):
    """Reponse pour un token du stock."""
    id: int
    token_uid: str
    token_type: str
    status: str
    hardware_uid: Optional[str] = None
    created_at: datetime
    last_assigned_at: Optional[datetime]
    # Infos assignation active (remplies si status == ASSIGNED)
    assigned_to: Optional[str] = None
    assigned_trip: Optional[str] = None

    model_config = {"from_attributes": True}


class TokenStatsResponse(BaseModel):
    """Statistiques du stock de tokens."""
    total: int
    available: int
    assigned: int
    damaged: int
    lost: int


class TokenStatusUpdate(BaseModel):
    """Mise a jour du statut d'un token."""
    status: str

    @field_validator("status")
    @classmethod
    def valid_status(cls, v: str) -> str:
        if v not in VALID_TOKEN_STATUSES:
            raise ValueError(f"Statut invalide. Valeurs acceptees : {VALID_TOKEN_STATUSES}")
        return v


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
    """Eleve inscrit a un voyage avec ses assignations (primaire physique + secondaire digitale)."""
    id: uuid.UUID
    first_name: str
    last_name: str
    email: Optional[str]
    # Assignation primaire (NFC_PHYSICAL ou QR_PHYSICAL)
    assignment_id: Optional[int] = None
    token_uid: Optional[str] = None
    assignment_type: Optional[str] = None
    assigned_at: Optional[datetime] = None
    # Assignation secondaire (QR_DIGITAL)
    secondary_assignment_id: Optional[int] = None
    secondary_token_uid: Optional[str] = None
    secondary_assignment_type: Optional[str] = None
    secondary_assigned_at: Optional[datetime] = None

    model_config = {"from_attributes": True}


class TripStudentsResponse(BaseModel):
    """Liste complete des eleves d'un voyage avec leur statut d'assignation."""
    trip_id: uuid.UUID
    total: int
    assigned: int
    unassigned: int
    assigned_digital: int = 0
    students: List[TripStudentWithAssignment]
