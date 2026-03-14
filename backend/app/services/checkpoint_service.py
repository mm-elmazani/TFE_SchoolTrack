"""
Service métier pour les checkpoints (US 2.5 + US 2.7 + US 4.4).
Création dynamique et clôture sur le terrain par les enseignants.
Timeline et résumé checkpoints pour la direction.
"""

import uuid
from datetime import datetime, timezone

from sqlalchemy.orm import Session
from sqlalchemy import func

from app.models.attendance import Attendance
from app.models.checkpoint import Checkpoint
from app.models.trip import Trip
from app.models.user import User
from app.schemas.checkpoint import (
    CheckpointCreate,
    CheckpointResponse,
    CheckpointsSummary,
    CheckpointTimelineEntry,
)


def create_checkpoint(
    db: Session,
    trip_id: uuid.UUID,
    data: CheckpointCreate,
) -> CheckpointResponse:
    """
    Crée un nouveau checkpoint en statut DRAFT pour un voyage donné.

    Le sequence_order est calculé automatiquement par le trigger PostgreSQL
    (set_checkpoint_sequence_order). On insère sans le fournir : le trigger
    le calcule avant INSERT et le remplira.

    Lève ValueError si le voyage est introuvable ou dans un statut incompatible
    (COMPLETED ou ARCHIVED).
    """
    trip = db.query(Trip).filter(Trip.id == trip_id).first()
    if trip is None:
        raise ValueError(f"Voyage {trip_id} introuvable.")
    if trip.status in ("COMPLETED", "ARCHIVED"):
        raise ValueError(
            f"Impossible de créer un checkpoint : le voyage est en statut {trip.status}."
        )

    # Calcul manuel du sequence_order (trigger PostgreSQL non disponible en test)
    max_order = (
        db.query(func.max(Checkpoint.sequence_order))
        .filter(Checkpoint.trip_id == trip_id)
        .scalar()
    )
    next_order = (max_order or 0) + 1

    checkpoint = Checkpoint(
        trip_id=trip_id,
        name=data.name,
        description=data.description,
        sequence_order=next_order,
        status="DRAFT",
    )
    db.add(checkpoint)
    db.commit()
    db.refresh(checkpoint)

    return CheckpointResponse.model_validate(checkpoint)


# ---------------------------------------------------------------------------
# US 4.4 — Timeline et résumé checkpoints
# ---------------------------------------------------------------------------


def get_checkpoints_summary(
    db: Session,
    trip_id: uuid.UUID,
) -> CheckpointsSummary:
    """
    Construit le résumé et la timeline des checkpoints d'un voyage.

    Inclut pour chaque checkpoint : nombre de scans, nombre d'élèves distincts
    scannés, durée (started_at → closed_at), nom du créateur.
    """
    trip = db.query(Trip).filter(Trip.id == trip_id).first()
    if trip is None:
        raise ValueError(f"Voyage {trip_id} introuvable.")

    checkpoints = (
        db.query(Checkpoint)
        .filter(Checkpoint.trip_id == trip_id)
        .order_by(Checkpoint.sequence_order)
        .all()
    )

    if not checkpoints:
        return CheckpointsSummary(
            trip_id=trip.id,
            trip_destination=trip.destination,
            total_checkpoints=0,
            active_checkpoints=0,
            closed_checkpoints=0,
            total_scans=0,
            avg_duration_minutes=None,
            timeline=[],
        )

    # Batch : scan counts par checkpoint
    scan_counts = dict(
        db.query(Attendance.checkpoint_id, func.count(Attendance.id))
        .filter(Attendance.checkpoint_id.in_([c.id for c in checkpoints]))
        .group_by(Attendance.checkpoint_id)
        .all()
    )

    # Batch : nombre d'élèves distincts par checkpoint
    student_counts = dict(
        db.query(
            Attendance.checkpoint_id,
            func.count(func.distinct(Attendance.student_id)),
        )
        .filter(Attendance.checkpoint_id.in_([c.id for c in checkpoints]))
        .group_by(Attendance.checkpoint_id)
        .all()
    )

    # Batch : noms des créateurs
    creator_ids = [c.created_by for c in checkpoints if c.created_by]
    creator_names = {}
    if creator_ids:
        users = db.query(User).filter(User.id.in_(creator_ids)).all()
        for u in users:
            first = u.first_name or ""
            last = u.last_name or ""
            creator_names[u.id] = f"{first} {last}".strip() or u.email

    # Construction timeline
    timeline = []
    durations = []
    total_scans = 0
    active_count = 0
    closed_count = 0

    for cp in checkpoints:
        sc = scan_counts.get(cp.id, 0)
        total_scans += sc

        if cp.status == "ACTIVE":
            active_count += 1
        elif cp.status == "CLOSED":
            closed_count += 1

        duration = None
        if cp.started_at and cp.closed_at:
            delta = cp.closed_at - cp.started_at
            duration = int(delta.total_seconds() / 60)
            durations.append(duration)

        entry = CheckpointTimelineEntry(
            id=cp.id,
            name=cp.name,
            description=cp.description,
            sequence_order=cp.sequence_order,
            status=cp.status,
            created_at=cp.created_at,
            started_at=cp.started_at,
            closed_at=cp.closed_at,
            created_by_name=creator_names.get(cp.created_by),
            scan_count=sc,
            student_count=student_counts.get(cp.id, 0),
            duration_minutes=duration,
        )
        timeline.append(entry)

    avg_duration = (
        round(sum(durations) / len(durations), 1) if durations else None
    )

    return CheckpointsSummary(
        trip_id=trip.id,
        trip_destination=trip.destination,
        total_checkpoints=len(checkpoints),
        active_checkpoints=active_count,
        closed_checkpoints=closed_count,
        total_scans=total_scans,
        avg_duration_minutes=avg_duration,
        timeline=timeline,
    )


def close_checkpoint(
    db: Session,
    checkpoint_id: uuid.UUID,
) -> CheckpointResponse:
    """
    Clôture un checkpoint ACTIVE → CLOSED.

    Enregistre closed_at avec le timestamp UTC courant.
    Lève ValueError si le checkpoint est introuvable, en statut DRAFT,
    ou déjà CLOSED.
    """
    checkpoint = db.query(Checkpoint).filter(Checkpoint.id == checkpoint_id).first()
    if checkpoint is None:
        raise ValueError(f"Checkpoint {checkpoint_id} introuvable.")
    if checkpoint.status == "DRAFT":
        raise ValueError("Impossible de clôturer un checkpoint en statut DRAFT.")
    if checkpoint.status == "CLOSED":
        raise ValueError("Le checkpoint est déjà clôturé.")

    checkpoint.status = "CLOSED"
    checkpoint.closed_at = datetime.now(timezone.utc)
    db.commit()
    db.refresh(checkpoint)

    return CheckpointResponse.model_validate(checkpoint)
