"""
Modele SQLAlchemy pour les alertes temps reel (US 4.3).
Table alerts : signalement eleve manquant, retard checkpoint, echec sync.
"""

import uuid
from sqlalchemy import Column, DateTime, ForeignKey, String, Text, func
from sqlalchemy.dialects.postgresql import UUID

from app.database import Base


class Alert(Base):
    """Alerte temps reel pour la direction."""
    __tablename__ = "alerts"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    trip_id = Column(UUID(as_uuid=True), ForeignKey("trips.id", ondelete="CASCADE"), nullable=False)
    checkpoint_id = Column(UUID(as_uuid=True), ForeignKey("checkpoints.id"), nullable=True)
    student_id = Column(UUID(as_uuid=True), ForeignKey("students.id"), nullable=False)

    alert_type = Column(String(50), nullable=False)      # STUDENT_MISSING, CHECKPOINT_DELAYED, SYNC_FAILED
    severity = Column(String(20), default="MEDIUM")       # LOW, MEDIUM, HIGH, CRITICAL
    message = Column(Text, nullable=True)
    status = Column(String(20), default="ACTIVE")          # ACTIVE, IN_PROGRESS, RESOLVED

    created_by = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
    resolved_by = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)

    created_at = Column(DateTime, server_default=func.now())
    resolved_at = Column(DateTime, nullable=True)
