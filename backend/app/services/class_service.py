"""
Service métier pour la gestion des classes scolaires (US 1.3).
"""

import uuid
import logging
from typing import Optional, Union

from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.models.school_class import ClassStudent, ClassTeacher, SchoolClass
from app.models.student import Student
from app.models.trip import Trip, TripClass, TripStudent
from app.schemas.school_class import (
    ClassCreate,
    ClassResponse,
    ClassStudentsAssign,
    ClassTeachersAssign,
    ClassUpdate,
)

logger = logging.getLogger(__name__)


def create_class(
    db: Session,
    data: ClassCreate,
    school_id: Optional[uuid.UUID] = None,
) -> ClassResponse:
    """
    Crée une nouvelle classe.
    Lève une ValueError si le nom existe déjà dans cette école.
    """
    school_class = SchoolClass(name=data.name, year=data.year, school_id=school_id)
    db.add(school_class)
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise ValueError(f"Une classe avec le nom '{data.name}' existe déjà dans cette école.")
    db.refresh(school_class)
    return _to_response(db, school_class)


def get_classes(db: Session, school_id: Optional[uuid.UUID] = None) -> list[ClassResponse]:
    query = select(SchoolClass)
    if school_id is not None:
        query = query.where(SchoolClass.school_id == school_id)
    classes = db.execute(query.order_by(SchoolClass.name)).scalars().all()
    return [_to_response(db, c) for c in classes]


def _get_owned_class(
    db: Session,
    class_id: uuid.UUID,
    school_id: Optional[uuid.UUID],
) -> Optional[SchoolClass]:
    if school_id is None:
        return db.get(SchoolClass, class_id)
    return db.execute(
        select(SchoolClass).where(
            SchoolClass.id == class_id,
            SchoolClass.school_id == school_id,
        )
    ).scalar_one_or_none()


def get_class(
    db: Session,
    class_id: uuid.UUID,
    school_id: Optional[uuid.UUID] = None,
) -> Optional[ClassResponse]:
    school_class = _get_owned_class(db, class_id, school_id)
    if school_class is None:
        return None
    return _to_response(db, school_class)


def update_class(
    db: Session,
    class_id: uuid.UUID,
    data: ClassUpdate,
    school_id: Optional[uuid.UUID] = None,
) -> Optional[ClassResponse]:
    school_class = _get_owned_class(db, class_id, school_id)
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


def delete_class(
    db: Session,
    class_id: uuid.UUID,
    school_id: Optional[uuid.UUID] = None,
) -> bool:
    """
    Supprime une classe.
    Bloqué si des élèves de cette classe participent à un voyage PLANNED ou ACTIVE.
    Retourne True si supprimé, False si introuvable.
    """
    school_class = _get_owned_class(db, class_id, school_id)
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


def _sync_trip_students_for_class(
    db: Session,
    class_id: uuid.UUID,
    student_ids_added: list[uuid.UUID],
) -> None:
    """Ajoute les eleves dans `trip_students` pour les voyages PLANNED/ACTIVE
    lies a cette classe via `trip_classes`.

    Idempotent : ignore les liens existants. Ne touche pas aux voyages
    COMPLETED/ARCHIVED (preserve l'historique des presences).
    """
    if not student_ids_added:
        return

    # Voyages encore modifiables lies a cette classe
    trip_ids = db.execute(
        select(Trip.id)
        .join(TripClass, TripClass.trip_id == Trip.id)
        .where(
            TripClass.class_id == class_id,
            Trip.status.in_(["PLANNED", "ACTIVE"]),
        )
    ).scalars().all()

    if not trip_ids:
        return

    # Liens deja presents pour eviter doublons (composite unique trip_id+student_id)
    existing = set(db.execute(
        select(TripStudent.trip_id, TripStudent.student_id)
        .where(
            TripStudent.trip_id.in_(trip_ids),
            TripStudent.student_id.in_(student_ids_added),
        )
    ).all())

    rows = []
    for tid in trip_ids:
        for sid in student_ids_added:
            if (tid, sid) in existing:
                continue
            rows.append({"trip_id": tid, "student_id": sid})

    if rows:
        db.bulk_insert_mappings(TripStudent, rows)


def _remove_trip_students_for_class(
    db: Session,
    class_id: uuid.UUID,
    student_id: uuid.UUID,
) -> None:
    """Retire un eleve des `trip_students` pour les voyages PLANNED/ACTIVE
    lies a cette classe via `trip_classes`.

    Ne touche pas aux voyages COMPLETED/ARCHIVED (historique).
    """
    trip_ids = db.execute(
        select(Trip.id)
        .join(TripClass, TripClass.trip_id == Trip.id)
        .where(
            TripClass.class_id == class_id,
            Trip.status.in_(["PLANNED", "ACTIVE"]),
        )
    ).scalars().all()

    if not trip_ids:
        return

    links = db.execute(
        select(TripStudent).where(
            TripStudent.trip_id.in_(trip_ids),
            TripStudent.student_id == student_id,
        )
    ).scalars().all()

    for link in links:
        db.delete(link)


def assign_students(
    db: Session,
    class_id: uuid.UUID,
    data: ClassStudentsAssign,
    school_id: Optional[uuid.UUID] = None,
) -> ClassResponse:
    """
    Assigne des élèves à une classe.
    Un élève ne peut appartenir qu'à une seule classe : s'il est déjà dans
    une autre classe, il en est retiré automatiquement avant d'être ajouté.
    Les élèves déjà dans cette classe sont ignorés (pas de doublon).

    Effet de bord : les eleves ajoutes sont aussi inseres dans `trip_students`
    pour tous les voyages PLANNED/ACTIVE lies a cette classe (les voyages
    COMPLETED/ARCHIVED ne sont pas modifies — historique preserve).
    """
    school_class = _get_owned_class(db, class_id, school_id)
    if school_class is None:
        raise ValueError("Classe introuvable.")

    # Récupérer les élèves déjà dans cette classe
    existing = set(db.execute(
        select(ClassStudent.student_id)
        .where(ClassStudent.class_id == class_id)
    ).scalars().all())

    to_insert = []
    newly_added_ids: list[uuid.UUID] = []
    for sid in data.student_ids:
        if sid in existing:
            continue
        # Retirer l'élève de toutes ses anciennes classes (un élève = une seule classe)
        old_links = db.execute(
            select(ClassStudent).where(ClassStudent.student_id == sid)
        ).scalars().all()
        for old_link in old_links:
            db.delete(old_link)
        to_insert.append({"class_id": class_id, "student_id": sid})
        newly_added_ids.append(sid)

    if to_insert:
        db.flush()  # S'assurer que les DELETE sont envoyés avant les INSERT
        db.bulk_insert_mappings(ClassStudent, to_insert)
        # Propagation aux voyages PLANNED/ACTIVE lies a cette classe
        _sync_trip_students_for_class(db, class_id, newly_added_ids)
        db.commit()

    return _to_response(db, school_class)


def remove_student(
    db: Session,
    class_id: uuid.UUID,
    student_id: uuid.UUID,
    school_id: Optional[uuid.UUID] = None,
) -> bool:
    """Retire un élève d'une classe. Retourne True si retiré, False si lien inexistant.

    Effet de bord : l'eleve est aussi retire des voyages PLANNED/ACTIVE lies
    a cette classe (les voyages COMPLETED/ARCHIVED ne sont pas modifies —
    historique preserve).
    """
    # Vérifier d'abord que la classe appartient à l'école (sinon 404)
    if _get_owned_class(db, class_id, school_id) is None:
        return False
    link = db.get(ClassStudent, (class_id, student_id))
    if link is None:
        return False
    db.delete(link)
    # Nettoyer trip_students pour les voyages encore modifiables
    _remove_trip_students_for_class(db, class_id, student_id)
    db.commit()
    return True


def assign_teachers(
    db: Session,
    class_id: uuid.UUID,
    data: ClassTeachersAssign,
    school_id: Optional[uuid.UUID] = None,
) -> ClassResponse:
    """
    Assigne des enseignants à une classe.
    Les enseignants déjà assignés sont ignorés.
    """
    school_class = _get_owned_class(db, class_id, school_id)
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


def remove_teacher(
    db: Session,
    class_id: uuid.UUID,
    teacher_id: uuid.UUID,
    school_id: Optional[uuid.UUID] = None,
) -> bool:
    if _get_owned_class(db, class_id, school_id) is None:
        return False
    link = db.get(ClassTeacher, (class_id, teacher_id))
    if link is None:
        return False
    db.delete(link)
    db.commit()
    return True


def _to_response(db: Session, school_class: SchoolClass) -> ClassResponse:
    nb_students = db.execute(
        select(func.count())
        .select_from(ClassStudent)
        .join(Student, Student.id == ClassStudent.student_id)
        .where(ClassStudent.class_id == school_class.id)
        .where(Student.school_id == school_class.school_id)
        .where(Student.is_deleted == False)  # noqa: E712
    ).scalar() or 0

    nb_teachers = db.execute(
        select(func.count())
        .select_from(ClassTeacher)
        .where(ClassTeacher.class_id == school_class.id)
    ).scalar() or 0

    return ClassResponse(
        id=school_class.id,
        school_id=school_class.school_id,
        name=school_class.name,
        year=school_class.year,
        nb_students=nb_students,
        nb_teachers=nb_teachers,
        created_at=school_class.created_at,
        updated_at=school_class.updated_at,
    )
