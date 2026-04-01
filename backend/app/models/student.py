"""
Modèle SQLAlchemy pour la table students.
Mapping vers le schéma v4.2 : pas de colonne UID ni classe (normalisé).
Champs PII chiffres AES-256-GCM au repos (US 6.3).
Suppression logique (soft delete) pour conformite RGPD (US 6.5).
"""

import uuid
from sqlalchemy import Boolean, Column, DateTime, ForeignKey, String, func
from sqlalchemy.dialects.postgresql import UUID

from app.database import Base
from app.services.crypto_service import EncryptedString


class Student(Base):
    __tablename__ = "students"

    id        = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    school_id = Column(UUID(as_uuid=True), ForeignKey("schools.id"), nullable=False)
    first_name = Column(EncryptedString(), nullable=False)
    last_name = Column(EncryptedString(), nullable=False)
    email = Column(EncryptedString(), nullable=True)
    phone = Column(EncryptedString(), nullable=True)
    photo_url = Column(String(500), nullable=True)
    parent_consent = Column(Boolean, default=False)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    # US 6.5 — Suppression logique RGPD
    is_deleted = Column(Boolean, nullable=False, default=False, server_default="false")
    deleted_at = Column(DateTime, nullable=True)
    deleted_by = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
