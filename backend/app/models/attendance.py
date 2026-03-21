"""
Modèles SQLAlchemy pour les présences scannées (offline-first, US 3.1 + US 3.2).

Architecture offline-first :
- client_uuid     : généré côté Flutter (package uuid), clé d'idempotence
- scanned_at      : timestamp local du client (avant sync réseau)
- Attendance      : table canonique — 1 ligne par (student, checkpoint, trip) = scan le plus ancien
- AttendanceHistory : archive de TOUS les scans bruts reçus (US 3.2)
"""

import uuid
from sqlalchemy import Boolean, Column, DateTime, ForeignKey, Integer, String, Text, func
from sqlalchemy.dialects.postgresql import UUID

from app.database import Base


class Attendance(Base):
    """Présence canonique — 1 ligne par (student, checkpoint, trip), timestamp le plus ancien."""
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


class AttendanceHistory(Base):
    """
    Archive brute de tous les scans reçus via synchronisation (US 3.2).

    Chaque appel à POST /api/sync/attendances insère ici TOUS les scans
    (sauf doublons de client_uuid déjà connus). merge_status indique le
    résultat de la fusion avec la table canonique `attendances`.
    """
    __tablename__ = "attendance_history"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    client_uuid = Column(UUID(as_uuid=True), unique=True, nullable=False)

    trip_id = Column(UUID(as_uuid=True), ForeignKey("trips.id", ondelete="CASCADE"), nullable=False)
    checkpoint_id = Column(UUID(as_uuid=True), ForeignKey("checkpoints.id", ondelete="CASCADE"), nullable=False)
    student_id = Column(UUID(as_uuid=True), ForeignKey("students.id", ondelete="CASCADE"), nullable=False)

    scanned_at = Column(DateTime, nullable=False)
    scanned_by = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
    scan_method = Column(String(20), nullable=False)
    scan_sequence = Column(Integer, default=1)
    is_manual = Column(Boolean, default=False)
    justification = Column(String(50), nullable=True)
    comment = Column(Text, nullable=True)

    device_id = Column(String(255), nullable=True)
    sync_session_id = Column(UUID(as_uuid=True), nullable=False)
    synced_at = Column(DateTime, server_default=func.now())

    # ACCEPTED      : premier scan pour ce (student, checkpoint) → inséré en canonique
    # MERGED_OLDEST : ce scan était plus ancien → a remplacé le canonique existant
    # SUPERSEDED    : ce scan était plus récent → canonique (plus ancien) conservé
    merge_status = Column(String(20), nullable=False, default="ACCEPTED")
