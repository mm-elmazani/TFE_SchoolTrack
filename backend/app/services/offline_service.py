"""
Service de génération du bundle offline (US 2.1).
Endpoint : GET /api/v1/trips/{trip_id}/offline-data

Agrège en une seule réponse tout ce dont Flutter a besoin pour fonctionner
sans réseau : voyage + élèves (avec assignation active) + checkpoints.
"""

import uuid
import logging
from datetime import datetime, timezone

from sqlalchemy import and_, select
from sqlalchemy.orm import Session

from app.models.assignment import Assignment
from app.models.checkpoint import Checkpoint
from app.models.student import Student
from app.models.trip import Trip, TripStudent
from app.schemas.offline import (
    OfflineAssignment,
    OfflineCheckpoint,
    OfflineDataBundle,
    OfflineStudent,
    OfflineTripInfo,
)

logger = logging.getLogger(__name__)


def get_offline_data(db: Session, trip_id: uuid.UUID) -> OfflineDataBundle:
    """
    Génère le bundle complet de données offline pour un voyage.

    Contenu :
    - Infos du voyage
    - Liste des élèves avec leur assignation active (LEFT JOIN)
    - Checkpoints existants triés par sequence_order

    Lève ValueError si le voyage est introuvable ou archivé.
    """
    # Vérifier que le voyage existe et est disponible
    trip = db.execute(select(Trip).where(Trip.id == trip_id)).scalar()
    if not trip:
        raise ValueError("Voyage introuvable.")
    if trip.status == "ARCHIVED":
        raise ValueError("Les données offline ne sont pas disponibles pour un voyage archivé.")

    # Eleves inscrits au voyage (sans JOIN assignation pour eviter les doublons)
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

    # Map student_id → liste de toutes les assignations actives
    assignment_map: dict[uuid.UUID, list[Assignment]] = {}
    for a in assignments:
        assignment_map.setdefault(a.student_id, []).append(a)

    # Tri alphabetique en Python (colonnes chiffrees, US 6.3)
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
        # Rétro-compat : assignment = physique en priorité, sinon premier disponible
        primary = next(
            (oa for oa in offline_assignments if oa.assignment_type in ("NFC_PHYSICAL", "QR_PHYSICAL")),
            offline_assignments[0] if offline_assignments else None,
        )
        students.append(
            OfflineStudent(
                id=student.id,
                first_name=student.first_name,
                last_name=student.last_name,
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
        "Bundle offline généré — voyage %s : %d élèves, %d checkpoints",
        trip_id, len(students), len(checkpoints),
    )

    return OfflineDataBundle(
        trip=OfflineTripInfo(
            id=trip.id,
            destination=trip.destination,
            date=trip.date,
            description=trip.description,
            status=trip.status,
        ),
        students=students,
        checkpoints=checkpoints,
        generated_at=datetime.now(timezone.utc),
    )
