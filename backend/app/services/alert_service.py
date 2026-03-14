"""
Service metier pour les alertes temps reel (US 4.3).
Creation, lecture, traitement et resolution des alertes.
"""

import uuid
import logging
from datetime import datetime
from typing import Optional

from sqlalchemy import select, func
from sqlalchemy.orm import Session

from app.models.alert import Alert
from app.models.checkpoint import Checkpoint
from app.models.student import Student
from app.models.trip import Trip
from app.schemas.alert import AlertCreate, AlertResponse, AlertStats, AlertUpdate

logger = logging.getLogger(__name__)


def create_alert(
    db: Session, data: AlertCreate, created_by: Optional[uuid.UUID] = None
) -> AlertResponse:
    """Cree une nouvelle alerte et retourne la reponse enrichie."""
    # Verifier que le voyage existe
    trip = db.get(Trip, data.trip_id)
    if trip is None:
        raise ValueError("Voyage introuvable.")

    # Verifier que l'eleve existe
    student = db.get(Student, data.student_id)
    if student is None:
        raise ValueError("Eleve introuvable.")

    alert = Alert(
        trip_id=data.trip_id,
        checkpoint_id=data.checkpoint_id,
        student_id=data.student_id,
        alert_type=data.alert_type,
        severity=data.severity,
        message=data.message,
        status="ACTIVE",
        created_by=created_by,
    )
    db.add(alert)
    db.commit()
    db.refresh(alert)

    logger.info("Alerte creee : %s (%s) pour eleve %s", alert.alert_type, alert.id, data.student_id)

    return _to_response(db, alert)


def get_alerts(
    db: Session,
    trip_id: Optional[uuid.UUID] = None,
    status_filter: Optional[str] = None,
) -> list[AlertResponse]:
    """Retourne les alertes avec filtres optionnels, triees par date desc."""
    query = select(Alert).order_by(Alert.created_at.desc())

    if trip_id:
        query = query.where(Alert.trip_id == trip_id)

    if status_filter and status_filter != "ALL":
        query = query.where(Alert.status == status_filter)

    alerts = db.execute(query).scalars().all()
    return [_to_response(db, a) for a in alerts]


def get_active_alerts(db: Session, trip_id: Optional[uuid.UUID] = None) -> list[AlertResponse]:
    """Retourne uniquement les alertes ACTIVE et IN_PROGRESS."""
    query = (
        select(Alert)
        .where(Alert.status.in_(["ACTIVE", "IN_PROGRESS"]))
        .order_by(Alert.created_at.desc())
    )
    if trip_id:
        query = query.where(Alert.trip_id == trip_id)

    alerts = db.execute(query).scalars().all()
    return [_to_response(db, a) for a in alerts]


def update_alert_status(
    db: Session,
    alert_id: uuid.UUID,
    data: AlertUpdate,
    resolved_by: Optional[uuid.UUID] = None,
) -> AlertResponse:
    """Met a jour le statut d'une alerte (IN_PROGRESS ou RESOLVED)."""
    alert = db.get(Alert, alert_id)
    if alert is None:
        raise ValueError("Alerte introuvable.")

    alert.status = data.status
    if data.status == "RESOLVED":
        alert.resolved_at = datetime.now()
        alert.resolved_by = resolved_by

    db.commit()
    db.refresh(alert)

    logger.info("Alerte %s → %s", alert.id, data.status)
    return _to_response(db, alert)


def get_alert_stats(db: Session, trip_id: Optional[uuid.UUID] = None) -> AlertStats:
    """Retourne les compteurs d'alertes."""
    base = select(func.count()).select_from(Alert)
    if trip_id:
        base = base.where(Alert.trip_id == trip_id)

    total = db.execute(base).scalar() or 0
    active = db.execute(base.where(Alert.status == "ACTIVE")).scalar() or 0
    in_progress = db.execute(base.where(Alert.status == "IN_PROGRESS")).scalar() or 0
    resolved = db.execute(base.where(Alert.status == "RESOLVED")).scalar() or 0
    critical = db.execute(base.where(Alert.severity == "CRITICAL")).scalar() or 0

    return AlertStats(
        total=total,
        active=active,
        in_progress=in_progress,
        resolved=resolved,
        critical=critical,
    )


def _to_response(db: Session, alert: Alert) -> AlertResponse:
    """Enrichit une alerte avec les noms d'eleve, voyage et checkpoint."""
    student_name = None
    student = db.get(Student, alert.student_id)
    if student:
        if student.is_deleted:
            student_name = "[Supprime]"
        else:
            student_name = f"{student.last_name} {student.first_name}"

    trip_destination = None
    trip = db.get(Trip, alert.trip_id)
    if trip:
        trip_destination = trip.destination

    checkpoint_name = None
    if alert.checkpoint_id:
        cp = db.get(Checkpoint, alert.checkpoint_id)
        if cp:
            checkpoint_name = cp.name

    return AlertResponse(
        id=alert.id,
        trip_id=alert.trip_id,
        checkpoint_id=alert.checkpoint_id,
        student_id=alert.student_id,
        student_name=student_name,
        trip_destination=trip_destination,
        checkpoint_name=checkpoint_name,
        alert_type=alert.alert_type,
        severity=alert.severity,
        message=alert.message,
        status=alert.status,
        created_by=alert.created_by,
        resolved_by=alert.resolved_by,
        created_at=alert.created_at,
        resolved_at=alert.resolved_at,
    )
