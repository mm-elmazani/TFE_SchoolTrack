"""
Modèle SQLAlchemy pour les écoles (US 6.6 — multi-tenancy).
Chaque école isole ses données via school_id sur les tables parentes.
"""

import uuid
from sqlalchemy import Boolean, Column, DateTime, String, func
from sqlalchemy.dialects.postgresql import UUID

from app.database import Base


class School(Base):
    __tablename__ = "schools"

    id         = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    name       = Column(String(255), nullable=False)
    slug       = Column(String(100), unique=True, nullable=False)
    is_active  = Column(Boolean, nullable=False, default=True)
    created_at = Column(DateTime, server_default=func.now())
