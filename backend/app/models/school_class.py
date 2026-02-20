"""
Modèles SQLAlchemy pour les classes et leurs associations.
Nommé school_class pour éviter le conflit avec le mot-clé Python 'class'.
"""

import uuid
from sqlalchemy import Column, DateTime, ForeignKey, String, func
from sqlalchemy.dialects.postgresql import UUID

from app.database import Base


class SchoolClass(Base):
    __tablename__ = "classes"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    name = Column(String(100), unique=True, nullable=False)
    year = Column(String(20), nullable=True)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())


class ClassStudent(Base):
    """Association classe ↔ élèves (3FN, v4.2)."""
    __tablename__ = "class_students"

    class_id = Column(UUID(as_uuid=True), ForeignKey("classes.id", ondelete="CASCADE"), primary_key=True)
    student_id = Column(UUID(as_uuid=True), ForeignKey("students.id", ondelete="CASCADE"), primary_key=True)
    enrolled_at = Column(DateTime, server_default=func.now())


class ClassTeacher(Base):
    """Association classe ↔ enseignants responsables."""
    __tablename__ = "class_teachers"

    class_id = Column(UUID(as_uuid=True), ForeignKey("classes.id", ondelete="CASCADE"), primary_key=True)
    teacher_id = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    assigned_at = Column(DateTime, server_default=func.now())
