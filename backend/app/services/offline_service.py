"""
Service de génération du bundle offline (US 2.1).
Endpoint : GET /api/v1/trips/{trip_id}/offline-data

Agrège en une seule réponse tout ce dont Flutter a besoin pour fonctionner
sans réseau : voyage + élèves (avec assignation active, classe, contact) + checkpoints.
"""

import uuid
import logging
from datetime import datetime, timezone
from typing import Optional

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.assignment import Assignment
from app.models.checkpoint import Checkpoint
from app.models.school_class import ClassStudent, SchoolClass
from app.models.student import Student
from app.models.trip import Trip, TripClass, TripStudent
from app.schemas.offline import (
    OfflineAssignment,
    OfflineCheckpoint,
    OfflineDataBundle,
    OfflineStudent,
    OfflineTripInfo,
)

logger = logging.getLogger(__name__)


def get_offline_data(
    db: Session,
    trip_id: uuid.UUID,
    school_id: Optional[uuid.UUID] = None,
) -> OfflineDataBundle:
    """
    Génère le bundle complet de données offline pour un voyage.

    Contenu :
    - Infos du voyage (destination, date, classes participantes, nb élèves)
    - Liste des élèves avec assignation active, email, téléphone, photo, classe
    - Checkpoints existants triés par sequence_order

    Lève ValueError si le voyage est introuvable ou archivé.
    Si school_id est fourni, la recherche est restreinte à cette école (isolation multi-tenant).
    """
    # Vérifier que le voyage existe et est disponible
    trip_query = select(Trip).where(Trip.id == trip_id)
    if school_id is not None:
        trip_query = trip_query.where(Trip.school_id == school_id)
    trip = db.execute(trip_query).scalar()
    if not trip:
        raise ValueError("Voyage introuvable.")
    if trip.status == "ARCHIVED":
        raise ValueError("Les données offline ne sont pas disponibles pour un voyage archivé.")

    # Élèves inscrits au voyage
    students_rows = db.execute(
        select(Student)
        .join(TripStudent, TripStudent.student_id == Student.id)
        .where(TripStudent.trip_id == trip_id)
    ).scalars().all()

    # Assignations actives du voyage
    assignments = db.execute(
        select(Assignment)
        .where(
            Assignment.trip_id == trip_id,
            Assignment.released_at.is_(None),
        )
    ).scalars().all()

    # Map student_id → liste d'assignations actives
    assignment_map: dict[uuid.UUID, list[Assignment]] = {}
    for a in assignments:
        assignment_map.setdefault(a.student_id, []).append(a)

    # Map student_id → nom de classe (un élève = une classe)
    student_ids = [s.id for s in students_rows]
    class_name_map: dict[uuid.UUID, str] = {}
    if student_ids:
        class_rows = db.execute(
            select(ClassStudent.student_id, SchoolClass.name)
            .join(SchoolClass, SchoolClass.id == ClassStudent.class_id)
            .where(ClassStudent.student_id.in_(student_ids))
        ).all()
        class_name_map = {row[0]: row[1] for row in class_rows}

    # Classes du voyage (pour le résumé)
    trip_class_rows = db.execute(
        select(SchoolClass.name)
        .join(TripClass, TripClass.class_id == SchoolClass.id)
        .where(TripClass.trip_id == trip_id)
        .order_by(SchoolClass.name)
    ).scalars().all()
    trip_classes = list(trip_class_rows)

    # Tri alphabétique en Python (colonnes chiffrées, US 6.3)
    students_rows = sorted(
        students_rows,
        key=lambda s: ((s.last_name or "").lower(), (s.first_name or "").lower()),
    )

    students = []
    for student in students_rows:
        student_assignments = assignment_map.get(student.id, [])
        offline_assignments = [
            OfflineAssignment(
                token_uid=a.token_uid,
                assignment_type=a.assignment_type,
            )
            for a in student_assignments
        ]
        # Rétro-compat : physique en priorité, sinon premier disponible
        primary = next(
            (oa for oa in offline_assignments if oa.assignment_type in ("NFC_PHYSICAL", "QR_PHYSICAL")),
            offline_assignments[0] if offline_assignments else None,
        )
        students.append(
            OfflineStudent(
                id=student.id,
                first_name=student.first_name,
                last_name=student.last_name,
                email=student.email,
                phone=student.phone,
                photo_url=student.photo_url,
                class_name=class_name_map.get(student.id),
                assignment=primary,
                assignments=offline_assignments,
            )
        )

    # Checkpoints existants sur ce voyage (hors archivés), triés par ordre
    checkpoints_db = db.execute(
        select(Checkpoint)
        .where(
            Checkpoint.trip_id == trip_id,
            Checkpoint.status != "ARCHIVED",
        )
        .order_by(Checkpoint.sequence_order)
    ).scalars().all()

    checkpoints = [
        OfflineCheckpoint(
            id=cp.id,
            name=cp.name,
            sequence_order=cp.sequence_order,
            status=cp.status,
        )
        for cp in checkpoints_db
    ]

    logger.info(
        "Bundle offline généré — voyage %s : %d élèves, %d checkpoints, %d classes",
        trip_id, len(students), len(checkpoints), len(trip_classes),
    )

    return OfflineDataBundle(
        trip=OfflineTripInfo(
            id=trip.id,
            destination=trip.destination,
            date=trip.date,
            description=trip.description,
            status=trip.status,
            classes=trip_classes,
            student_count=len(students),
        ),
        students=students,
        checkpoints=checkpoints,
        generated_at=datetime.now(timezone.utc),
    )
