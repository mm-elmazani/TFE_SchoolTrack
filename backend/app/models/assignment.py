"""
Modèles SQLAlchemy pour les tokens (bracelets) et leurs assignations.
"""

import uuid
from sqlalchemy import Column, DateTime, ForeignKey, Integer, String, func
from sqlalchemy.dialects.postgresql import UUID

from app.database import Base


class Token(Base):
    """Stock de supports physiques (bracelets NFC, QR physiques)."""
    __tablename__ = "tokens"

    id = Column(Integer, primary_key=True, autoincrement=True)
    token_uid = Column(String(50), unique=True, nullable=False)  # Ex: "ST-001"
    token_type = Column(String(20), nullable=False)              # NFC_PHYSICAL, QR_PHYSICAL
    status = Column(String(20), default="AVAILABLE")             # AVAILABLE, ASSIGNED, DAMAGED, LOST
    created_at = Column(DateTime, server_default=func.now())
    last_assigned_at = Column(DateTime, nullable=True)


class Assignment(Base):
    """Liaison dynamique token ↔ élève ↔ voyage."""
    __tablename__ = "assignments"

    id = Column(Integer, primary_key=True, autoincrement=True)
    token_uid = Column(String(50), nullable=False)
    student_id = Column(UUID(as_uuid=True), ForeignKey("students.id", ondelete="CASCADE"), nullable=True)
    trip_id = Column(UUID(as_uuid=True), ForeignKey("trips.id", ondelete="CASCADE"), nullable=True)
    assignment_type = Column(String(20), nullable=False)  # NFC_PHYSICAL, QR_PHYSICAL, QR_DIGITAL
    assigned_at = Column(DateTime, server_default=func.now())
    assigned_by = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
    released_at = Column(DateTime, nullable=True)         # NULL = assignation active
    created_at = Column(DateTime, server_default=func.now())
