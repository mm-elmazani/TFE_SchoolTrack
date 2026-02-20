"""
Modèle SQLAlchemy pour les checkpoints (points de contrôle terrain).
Créés dynamiquement par les enseignants durant le voyage (US 2.5).
"""

import uuid
from sqlalchemy import Column, DateTime, ForeignKey, Integer, String, Text, func
from sqlalchemy.dialects.postgresql import UUID

from app.database import Base


class Checkpoint(Base):
    """Point de contrôle créé dynamiquement sur le terrain par un enseignant."""
    __tablename__ = "checkpoints"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    trip_id = Column(UUID(as_uuid=True), ForeignKey("trips.id", ondelete="CASCADE"), nullable=False)
    name = Column(String(255), nullable=False)
    description = Column(Text, nullable=True)
    sequence_order = Column(Integer, nullable=False)  # Calculé par trigger PostgreSQL

    created_by = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
    created_at = Column(DateTime, server_default=func.now())

    started_at = Column(DateTime, nullable=True)   # Premier scan effectué
    closed_at = Column(DateTime, nullable=True)    # NULL = checkpoint encore actif
    status = Column(String(20), default="DRAFT")   # DRAFT, ACTIVE, CLOSED, ARCHIVED

    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())
