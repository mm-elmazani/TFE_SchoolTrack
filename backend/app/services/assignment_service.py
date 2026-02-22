"""
Service métier pour l'assignation des bracelets aux élèves (US 1.5).
"""

import csv
import io
import uuid
import logging
from datetime import datetime
from typing import Optional

from sqlalchemy import and_, func, select
from sqlalchemy.orm import Session

from app.models.assignment import Assignment, Token
from app.models.student import Student
from app.models.trip import TripStudent
from app.schemas.assignment import (
    AssignmentCreate,
    AssignmentReassign,
    AssignmentResponse,
    TripAssignmentStatus,
    TripStudentWithAssignment,
    TripStudentsResponse,
)

logger = logging.getLogger(__name__)


def assign_token(
    db: Session,
    data: AssignmentCreate,
    assigned_by: Optional[uuid.UUID] = None,
) -> AssignmentResponse:
    """
    Assigne un bracelet à un élève pour un voyage.

    Validations :
    1. L'élève est bien inscrit au voyage (trip_students)
    2. Le token n'est pas déjà activement assigné sur ce voyage
    3. L'élève n'a pas déjà un token actif sur ce voyage
    """
    # 1. Vérifier que l'élève participe au voyage
    is_participant = db.execute(
        select(TripStudent)
        .where(
            TripStudent.trip_id == data.trip_id,
            TripStudent.student_id == data.student_id,
        )
    ).scalar()

    if not is_participant:
        raise ValueError("Cet élève n'est pas inscrit à ce voyage.")

    # 2. Vérifier que le token n'est pas déjà assigné sur ce voyage
    token_taken = db.execute(
        select(Assignment)
        .where(
            Assignment.token_uid == data.token_uid,
            Assignment.trip_id == data.trip_id,
            Assignment.released_at.is_(None),
        )
    ).scalar()

    if token_taken:
        raise ValueError(f"Le bracelet '{data.token_uid}' est déjà assigné sur ce voyage.")

    # 3. Vérifier que l'élève n'a pas déjà un bracelet actif sur ce voyage
    student_taken = db.execute(
        select(Assignment)
        .where(
            Assignment.student_id == data.student_id,
            Assignment.trip_id == data.trip_id,
            Assignment.released_at.is_(None),
        )
    ).scalar()

    if student_taken:
        raise ValueError("Cet élève a déjà un bracelet assigné sur ce voyage.")

    assignment = Assignment(
        token_uid=data.token_uid,
        student_id=data.student_id,
        trip_id=data.trip_id,
        assignment_type=data.assignment_type,
        assigned_by=assigned_by,
    )
    db.add(assignment)

    # Mettre à jour le statut du token physique si présent en BDD
    _update_token_status(db, data.token_uid, "ASSIGNED")

    db.commit()
    db.refresh(assignment)

    logger.info("Bracelet %s assigné à élève %s (voyage %s)", data.token_uid, data.student_id, data.trip_id)
    return AssignmentResponse.model_validate(assignment)


def reassign_token(
    db: Session,
    data: AssignmentReassign,
    assigned_by: Optional[uuid.UUID] = None,
) -> AssignmentResponse:
    """
    Réassigne un bracelet : libère toutes les assignations actives liées
    à ce token OU à cet élève sur ce voyage, puis crée une nouvelle assignation.
    """
    # Libérer l'assignation active du token sur ce voyage (si elle existe)
    old_token = db.execute(
        select(Assignment)
        .where(
            Assignment.token_uid == data.token_uid,
            Assignment.trip_id == data.trip_id,
            Assignment.released_at.is_(None),
        )
    ).scalar()

    if old_token:
        old_token.released_at = datetime.now()

    # Libérer l'assignation active de l'élève sur ce voyage (si elle existe)
    old_student = db.execute(
        select(Assignment)
        .where(
            Assignment.student_id == data.student_id,
            Assignment.trip_id == data.trip_id,
            Assignment.released_at.is_(None),
        )
    ).scalar()

    if old_student and old_student is not old_token:
        old_student.released_at = datetime.now()

    # Forcer l'envoi des UPDATEs à PostgreSQL AVANT l'INSERT.
    # Sans flush(), SQLAlchemy peut envoyer l'INSERT avant les UPDATEs,
    # ce qui viole le partial unique index (student_id, trip_id) WHERE released_at IS NULL
    # car l'ancienne ligne a encore released_at=NULL au moment de la vérification.
    db.flush()

    # Créer la nouvelle assignation
    assignment = Assignment(
        token_uid=data.token_uid,
        student_id=data.student_id,
        trip_id=data.trip_id,
        assignment_type=data.assignment_type,
        assigned_by=assigned_by,
    )
    db.add(assignment)
    _update_token_status(db, data.token_uid, "ASSIGNED")
    db.commit()
    db.refresh(assignment)

    logger.info(
        "Réassignation bracelet %s → élève %s (voyage %s) — justification : %s",
        data.token_uid, data.student_id, data.trip_id, data.justification
    )
    return AssignmentResponse.model_validate(assignment)


def get_trip_assignment_status(db: Session, trip_id: uuid.UUID) -> TripAssignmentStatus:
    """
    Retourne le statut complet des assignations pour un voyage :
    total élèves, élèves assignés, élèves non assignés, liste des assignations.
    """
    total_students = db.execute(
        select(func.count()).select_from(TripStudent).where(TripStudent.trip_id == trip_id)
    ).scalar() or 0

    assignments = db.execute(
        select(Assignment)
        .where(
            Assignment.trip_id == trip_id,
            Assignment.released_at.is_(None),
        )
    ).scalars().all()

    assigned_students = len(assignments)

    return TripAssignmentStatus(
        trip_id=trip_id,
        total_students=total_students,
        assigned_students=assigned_students,
        unassigned_students=total_students - assigned_students,
        assignments=[AssignmentResponse.model_validate(a) for a in assignments],
    )


def export_assignments_csv(db: Session, trip_id: uuid.UUID) -> str:
    """
    Génère un CSV des assignations actives d'un voyage.
    Retourne le contenu CSV sous forme de string (UTF-8 BOM pour Excel).
    """
    assignments = db.execute(
        select(Assignment)
        .where(
            Assignment.trip_id == trip_id,
            Assignment.released_at.is_(None),
        )
        .order_by(Assignment.assigned_at)
    ).scalars().all()

    output = io.StringIO()
    writer = csv.writer(output, delimiter=";")
    writer.writerow(["token_uid", "student_id", "assignment_type", "assigned_at"])

    for a in assignments:
        writer.writerow([
            a.token_uid,
            str(a.student_id),
            a.assignment_type,
            a.assigned_at.strftime("%Y-%m-%d %H:%M:%S") if a.assigned_at else "",
        ])

    return "\ufeff" + output.getvalue()  # BOM pour compatibilité Excel


def get_trip_students_with_assignments(
    db: Session, trip_id: uuid.UUID
) -> TripStudentsResponse:
    """
    Retourne la liste des élèves inscrits à un voyage avec leur bracelet actif (si assigné).
    Utilisé par le dashboard web pour l'écran d'assignation (US 1.5).
    """
    rows = db.execute(
        select(Student, Assignment)
        .join(TripStudent, TripStudent.student_id == Student.id)
        .outerjoin(
            Assignment,
            and_(
                Assignment.student_id == Student.id,
                Assignment.trip_id == trip_id,
                Assignment.released_at.is_(None),
            ),
        )
        .where(TripStudent.trip_id == trip_id)
        .order_by(Student.last_name, Student.first_name)
    ).all()

    students = []
    assigned_count = 0
    for student, assignment in rows:
        if assignment is not None:
            assigned_count += 1
        students.append(
            TripStudentWithAssignment(
                id=student.id,
                first_name=student.first_name,
                last_name=student.last_name,
                email=student.email,
                token_uid=assignment.token_uid if assignment else None,
                assignment_type=assignment.assignment_type if assignment else None,
                assigned_at=assignment.assigned_at if assignment else None,
            )
        )

    logger.info(
        "Statut assignations voyage %s : %d/%d élèves assignés",
        trip_id, assigned_count, len(students)
    )
    return TripStudentsResponse(
        trip_id=trip_id,
        total=len(students),
        assigned=assigned_count,
        unassigned=len(students) - assigned_count,
        students=students,
    )


def release_trip_tokens(db: Session, trip_id: uuid.UUID) -> int:
    """
    Libère toutes les assignations actives d'un voyage en settant released_at = NOW().

    Appelé automatiquement quand un voyage passe à COMPLETED ou ARCHIVED,
    ou manuellement via POST /api/v1/trips/{id}/release-tokens.

    Retourne le nombre d'assignations libérées (0 si aucune active).
    """
    assignments = db.execute(
        select(Assignment)
        .where(
            Assignment.trip_id == trip_id,
            Assignment.released_at.is_(None),
        )
    ).scalars().all()

    count = len(assignments)
    if count == 0:
        return 0

    now = datetime.now()
    for a in assignments:
        a.released_at = now

    db.commit()
    logger.info("Voyage %s : %d bracelet(s) libéré(s)", trip_id, count)
    return count


def _update_token_status(db: Session, token_uid: str, status: str) -> None:
    """Met à jour le statut d'un token physique s'il est enregistré en BDD."""
    token = db.execute(
        select(Token).where(Token.token_uid == token_uid)
    ).scalar()

    if token:
        token.status = status
        token.last_assigned_at = datetime.now()
