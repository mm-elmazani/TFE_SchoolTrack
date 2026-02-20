"""
Modèle SQLAlchemy pour les utilisateurs.
Version minimale — sera complété avec les champs auth en EPIC 6.
"""

import uuid
from sqlalchemy import Boolean, Column, DateTime, Integer, String, func
from sqlalchemy.dialects.postgresql import UUID

from app.database import Base


class User(Base):
    __tablename__ = "users"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    email = Column(String(255), unique=True, nullable=False)
    password_hash = Column(String(255), nullable=False)
    first_name = Column(String(100), nullable=True)
    last_name = Column(String(100), nullable=True)
    role = Column(String(50), nullable=False)  # DIRECTION, TEACHER, OBSERVER, ADMIN_TECH
    totp_secret = Column(String(100), nullable=True)
    is_2fa_enabled = Column(Boolean, default=False)
    failed_attempts = Column(Integer, default=0)
    last_login = Column(DateTime, nullable=True)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())
