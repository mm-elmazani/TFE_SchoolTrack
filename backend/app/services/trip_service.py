"""
Service métier pour les voyages (US 1.2).
Gère la création, la lecture, la modification et l'archivage des voyages.
"""

import uuid
import logging
from typing import Optional

from sqlalchemy import delete, func, select
from sqlalchemy.orm import Session

from app.models.school_class import ClassStudent
from app.models.trip import Trip, TripStudent
from app.schemas.trip import TripCreate, TripResponse, TripUpdate

logger = logging.getLogger(__name__)


def create_trip(db: Session, data: TripCreate, created_by: Optional[uuid.UUID] = None) -> TripResponse:
    """
    Crée un voyage et associe automatiquement les élèves des classes sélectionnées.

    Étapes :
    1. Créer l'entrée dans trips
    2. Récupérer les élèves des classes via class_students
    3. Insérer en bulk dans trip_students (dédupliqué)
    4. TODO US 1.6 : notifier les enseignants responsables par email
    """
    trip = Trip(
        destination=data.destination,
        date=data.date,
        description=data.description,
        created_by=created_by,
        status="PLANNED",
    )
    db.add(trip)
    db.flush()  # Obtenir l'ID avant le commit

    # Récupérer les élèves des classes sélectionnées (dédupliqué)
    student_ids = db.execute(
        select(ClassStudent.student_id)
        .where(ClassStudent.class_id.in_(data.class_ids))
        .distinct()
    ).scalars().all()

    if student_ids:
        db.bulk_insert_mappings(TripStudent, [
            {"trip_id": trip.id, "student_id": sid}
            for sid in student_ids
        ])

    db.commit()
    db.refresh(trip)

    # TODO US 1.6 : envoyer une notification email aux enseignants responsables des classes
    logger.info(
        "Voyage créé : %s (%s) — %d élèves associés",
        trip.destination, trip.id, len(student_ids)
    )

    return _to_response(db, trip)


def get_trips(db: Session) -> list[TripResponse]:
    """Retourne tous les voyages non supprimés, du plus récent au plus ancien."""
    trips = db.execute(
        select(Trip)
        .where(Trip.status != "ARCHIVED")
        .order_by(Trip.date.desc())
    ).scalars().all()

    return [_to_response(db, t) for t in trips]


def get_trip(db: Session, trip_id: uuid.UUID) -> Optional[TripResponse]:
    """Retourne un voyage par son ID, ou None s'il n'existe pas."""
    trip = db.get(Trip, trip_id)
    if trip is None:
        return None
    return _to_response(db, trip)


def update_trip(db: Session, trip_id: uuid.UUID, data: TripUpdate) -> Optional[TripResponse]:
    """
    Met à jour les champs modifiables d'un voyage.
    Si class_ids est fourni, les élèves du voyage sont recalculés depuis les nouvelles classes
    (suppression des anciens + insertion des nouveaux, dédupliqués).
    """
    trip = db.get(Trip, trip_id)
    if trip is None:
        return None

    # Mise à jour des champs scalaires (hors class_ids)
    update_data = data.model_dump(exclude_unset=True, exclude={"class_ids"})
    for field, value in update_data.items():
        setattr(trip, field, value)

    # Recalcul des élèves si de nouvelles classes sont fournies
    if data.class_ids is not None:
        # Supprimer les anciennes associations élèves
        db.execute(
            delete(TripStudent).where(TripStudent.trip_id == trip.id)
        )

        # Récupérer les élèves des nouvelles classes (dédupliqué)
        student_ids = db.execute(
            select(ClassStudent.student_id)
            .where(ClassStudent.class_id.in_(data.class_ids))
            .distinct()
        ).scalars().all()

        if student_ids:
            db.bulk_insert_mappings(TripStudent, [
                {"trip_id": trip.id, "student_id": sid}
                for sid in student_ids
            ])

    db.commit()
    db.refresh(trip)
    return _to_response(db, trip)


def archive_trip(db: Session, trip_id: uuid.UUID) -> bool:
    """
    Archive un voyage (suppression logique).
    Retourne True si archivé, False si non trouvé.
    """
    trip = db.get(Trip, trip_id)
    if trip is None:
        return False

    trip.status = "ARCHIVED"
    db.commit()
    return True


def _to_response(db: Session, trip: Trip) -> TripResponse:
    """Construit le schéma de réponse avec le total d'élèves."""
    total = db.execute(
        select(func.count())
        .select_from(TripStudent)
        .where(TripStudent.trip_id == trip.id)
    ).scalar() or 0

    return TripResponse(
        id=trip.id,
        destination=trip.destination,
        date=trip.date,
        description=trip.description,
        status=trip.status,
        total_students=total,
        created_at=trip.created_at,
        updated_at=trip.updated_at,
    )
