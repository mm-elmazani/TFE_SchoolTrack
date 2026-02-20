"""
Service métier pour la gestion des classes scolaires (US 1.3).
"""

import uuid
import logging
from typing import Optional

from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.models.school_class import ClassStudent, ClassTeacher, SchoolClass
from app.models.trip import Trip, TripStudent
from app.schemas.school_class import (
    ClassCreate,
    ClassResponse,
    ClassStudentsAssign,
    ClassTeachersAssign,
    ClassUpdate,
)

logger = logging.getLogger(__name__)


def create_class(db: Session, data: ClassCreate) -> ClassResponse:
    """
    Crée une nouvelle classe.
    Lève une ValueError si le nom existe déjà.
    """
    school_class = SchoolClass(name=data.name, year=data.year)
    db.add(school_class)
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise ValueError(f"Une classe avec le nom '{data.name}' existe déjà.")
    db.refresh(school_class)
    return _to_response(db, school_class)


def get_classes(db: Session) -> list[ClassResponse]:
    """Retourne toutes les classes, triées par nom."""
    classes = db.execute(
        select(SchoolClass).order_by(SchoolClass.name)
    ).scalars().all()
    return [_to_response(db, c) for c in classes]


def get_class(db: Session, class_id: uuid.UUID) -> Optional[ClassResponse]:
    """Retourne une classe par son ID, ou None si inexistante."""
    school_class = db.get(SchoolClass, class_id)
    if school_class is None:
        return None
    return _to_response(db, school_class)


def update_class(db: Session, class_id: uuid.UUID, data: ClassUpdate) -> Optional[ClassResponse]:
    """Met à jour les champs fournis d'une classe."""
    school_class = db.get(SchoolClass, class_id)
    if school_class is None:
        return None

    update_data = data.model_dump(exclude_unset=True)
    for field, value in update_data.items():
        setattr(school_class, field, value)

    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise ValueError(f"Une classe avec ce nom existe déjà.")
    db.refresh(school_class)
    return _to_response(db, school_class)


def delete_class(db: Session, class_id: uuid.UUID) -> bool:
    """
    Supprime une classe.
    Bloqué si des élèves de cette classe participent à un voyage PLANNED ou ACTIVE.
    Retourne True si supprimé, False si introuvable.
    """
    school_class = db.get(SchoolClass, class_id)
    if school_class is None:
        return False

    # Contrainte : vérifier les voyages actifs ou planifiés
    active_trip_id = db.execute(
        select(Trip.id)
        .join(TripStudent, TripStudent.trip_id == Trip.id)
        .join(ClassStudent, ClassStudent.student_id == TripStudent.student_id)
        .where(
            ClassStudent.class_id == class_id,
            Trip.status.in_(["PLANNED", "ACTIVE"]),
        )
        .limit(1)
    ).scalar()

    if active_trip_id:
        raise ValueError(
            "Impossible de supprimer cette classe : des élèves participent "
            "à un voyage planifié ou en cours."
        )

    db.delete(school_class)
    db.commit()
    return True


def assign_students(db: Session, class_id: uuid.UUID, data: ClassStudentsAssign) -> ClassResponse:
    """
    Assigne des élèves à une classe.
    Les élèves déjà assignés sont ignorés (pas de doublon).
    """
    school_class = db.get(SchoolClass, class_id)
    if school_class is None:
        raise ValueError("Classe introuvable.")

    # Récupérer les élèves déjà dans cette classe
    existing = set(db.execute(
        select(ClassStudent.student_id)
        .where(ClassStudent.class_id == class_id)
    ).scalars().all())

    to_insert = [
        {"class_id": class_id, "student_id": sid}
        for sid in data.student_ids
        if sid not in existing
    ]

    if to_insert:
        db.bulk_insert_mappings(ClassStudent, to_insert)
        db.commit()

    return _to_response(db, school_class)


def remove_student(db: Session, class_id: uuid.UUID, student_id: uuid.UUID) -> bool:
    """Retire un élève d'une classe. Retourne True si retiré, False si lien inexistant."""
    link = db.get(ClassStudent, (class_id, student_id))
    if link is None:
        return False
    db.delete(link)
    db.commit()
    return True


def assign_teachers(db: Session, class_id: uuid.UUID, data: ClassTeachersAssign) -> ClassResponse:
    """
    Assigne des enseignants à une classe.
    Les enseignants déjà assignés sont ignorés.
    """
    school_class = db.get(SchoolClass, class_id)
    if school_class is None:
        raise ValueError("Classe introuvable.")

    existing = set(db.execute(
        select(ClassTeacher.teacher_id)
        .where(ClassTeacher.class_id == class_id)
    ).scalars().all())

    to_insert = [
        {"class_id": class_id, "teacher_id": tid}
        for tid in data.teacher_ids
        if tid not in existing
    ]

    if to_insert:
        db.bulk_insert_mappings(ClassTeacher, to_insert)
        db.commit()

    return _to_response(db, school_class)


def remove_teacher(db: Session, class_id: uuid.UUID, teacher_id: uuid.UUID) -> bool:
    """Retire un enseignant d'une classe. Retourne True si retiré, False si lien inexistant."""
    link = db.get(ClassTeacher, (class_id, teacher_id))
    if link is None:
        return False
    db.delete(link)
    db.commit()
    return True


def _to_response(db: Session, school_class: SchoolClass) -> ClassResponse:
    """Construit le schéma de réponse avec les compteurs élèves et enseignants."""
    nb_students = db.execute(
        select(func.count())
        .select_from(ClassStudent)
        .where(ClassStudent.class_id == school_class.id)
    ).scalar() or 0

    nb_teachers = db.execute(
        select(func.count())
        .select_from(ClassTeacher)
        .where(ClassTeacher.class_id == school_class.id)
    ).scalar() or 0

    return ClassResponse(
        id=school_class.id,
        name=school_class.name,
        year=school_class.year,
        nb_students=nb_students,
        nb_teachers=nb_teachers,
        created_at=school_class.created_at,
        updated_at=school_class.updated_at,
    )
