"""
Service métier pour les checkpoints (US 2.5 + US 2.7).
Création dynamique et clôture sur le terrain par les enseignants.
"""

import uuid
from datetime import datetime, timezone

from sqlalchemy.orm import Session
from sqlalchemy import func

from app.models.checkpoint import Checkpoint
from app.models.trip import Trip
from app.schemas.checkpoint import CheckpointCreate, CheckpointResponse


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
