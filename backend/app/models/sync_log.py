"""Modèle SQLAlchemy pour la table sync_logs."""

import uuid

from sqlalchemy import Column, DateTime, ForeignKey, Integer, String, Text, func
from sqlalchemy.dialects.postgresql import JSONB, UUID

from app.database import Base


class SyncLog(Base):
    __tablename__ = "sync_logs"

    id = Column(Integer, primary_key=True, autoincrement=True)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
    trip_id = Column(UUID(as_uuid=True), ForeignKey("trips.id"), nullable=True)
    device_id = Column(String(255), nullable=True)
    records_synced = Column(Integer, default=0)
    conflicts_detected = Column(Integer, default=0)
    status = Column(String(20), nullable=True)  # SUCCESS, PARTIAL, FAILED
    error_details = Column(JSONB, nullable=True)
    synced_at = Column(DateTime, server_default=func.now())
