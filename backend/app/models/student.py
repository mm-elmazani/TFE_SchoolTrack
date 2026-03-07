"""
Modèle SQLAlchemy pour la table students.
Mapping vers le schéma v4.2 : pas de colonne UID ni classe (normalisé).
Champs PII chiffres AES-256-GCM au repos (US 6.3).
"""

import uuid
from sqlalchemy import Boolean, Column, DateTime, String, func
from sqlalchemy.dialects.postgresql import UUID

from app.database import Base
from app.services.crypto_service import EncryptedString


class Student(Base):
    __tablename__ = "students"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    first_name = Column(EncryptedString(), nullable=False)
    last_name = Column(EncryptedString(), nullable=False)
    email = Column(EncryptedString(), nullable=True)
    photo_url = Column(String(500), nullable=True)
    parent_consent = Column(Boolean, default=False)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())
