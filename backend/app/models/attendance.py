"""
Modèle SQLAlchemy pour les présences scannées (offline-first).

Architecture offline-first :
- client_uuid : généré côté Flutter (package uuid), clé d'idempotence
- scanned_at  : timestamp local du client (avant sync réseau)
- Les enregistrements sont créés sur SQLite local, puis synchronisés via POST /api/sync/attendances
"""

import uuid
from sqlalchemy import Boolean, Column, DateTime, ForeignKey, Integer, String, Text, func
from sqlalchemy.dialects.postgresql import UUID

from app.database import Base


class Attendance(Base):
    """Présence scannée — supporte les scans NFC, QR physique, QR digital et manuel."""
    __tablename__ = "attendances"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    client_uuid = Column(UUID(as_uuid=True), unique=True, nullable=True)  # Clé idempotence (offline-first)

    trip_id = Column(UUID(as_uuid=True), ForeignKey("trips.id", ondelete="CASCADE"), nullable=False)
    checkpoint_id = Column(UUID(as_uuid=True), ForeignKey("checkpoints.id", ondelete="CASCADE"), nullable=False)
    student_id = Column(UUID(as_uuid=True), ForeignKey("students.id", ondelete="CASCADE"), nullable=False)
    assignment_id = Column(Integer, ForeignKey("assignments.id"), nullable=True)

    scanned_at = Column(DateTime, nullable=False)          # Timestamp client (offline)
    scanned_by = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
    scan_method = Column(String(20), nullable=False)        # NFC, QR_PHYSICAL, QR_DIGITAL, MANUAL
    scan_sequence = Column(Integer, default=1)              # Numéro de scan au checkpoint

    is_manual = Column(Boolean, default=False)
    justification = Column(String(50), nullable=True)       # Raison si manuel
    comment = Column(Text, nullable=True)

    created_at = Column(DateTime, server_default=func.now())
