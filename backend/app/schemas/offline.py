"""
Schémas Pydantic pour le bundle de données offline (US 2.1).
Endpoint : GET /api/v1/trips/{trip_id}/offline-data

Ce bundle contient tout ce dont l'app Flutter a besoin pour fonctionner sans réseau :
- Les infos du voyage
- Les élèves avec leur assignation active (bracelet/QR)
- Les checkpoints existants
"""

import uuid
from datetime import date, datetime
from typing import List, Optional

from pydantic import BaseModel


class OfflineTripInfo(BaseModel):
    """Informations essentielles du voyage pour le mode offline."""
    id: uuid.UUID
    destination: str
    date: date
    description: Optional[str]
    status: str
    classes: List[str] = []       # Noms des classes participant au voyage
    student_count: int = 0        # Nombre total d'élèves inscrits


class OfflineAssignment(BaseModel):
    """Assignation active de l'élève (bracelet NFC, QR physique ou QR digital)."""
    token_uid: str
    assignment_type: str  # NFC_PHYSICAL, QR_PHYSICAL, QR_DIGITAL


class OfflineStudent(BaseModel):
    """Élève avec ses assignations de bracelet/QR et ses données personnelles."""
    id: uuid.UUID
    first_name: str
    last_name: str
    email: Optional[str] = None
    phone: Optional[str] = None
    photo_url: Optional[str] = None   # Chemin relatif — à préfixer avec l'URL API
    class_name: Optional[str] = None  # Nom de la classe de l'élève
    assignment: Optional[OfflineAssignment] = None  # Rétro-compat : assignation primaire
    assignments: List[OfflineAssignment] = []        # Toutes les assignations actives


class OfflineCheckpoint(BaseModel):
    """Point de contrôle existant sur le voyage."""
    id: uuid.UUID
    name: str
    sequence_order: int
    status: str  # DRAFT, ACTIVE, CLOSED


class OfflineDataBundle(BaseModel):
    """
    Bundle complet téléchargé par Flutter avant de partir en mode offline.
    Stocké dans SQLite local sur le téléphone de l'enseignant.
    """
    trip: OfflineTripInfo
    students: List[OfflineStudent]
    checkpoints: List[OfflineCheckpoint]
    generated_at: datetime  # Timestamp UTC de génération du bundle
