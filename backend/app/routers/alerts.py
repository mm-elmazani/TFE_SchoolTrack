"""
Router pour les alertes temps reel (US 4.3).
Creation : DIRECTION, ADMIN_TECH, TEACHER.
Lecture : DIRECTION, ADMIN_TECH.
Mise a jour statut : DIRECTION, ADMIN_TECH.
"""

import uuid
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from sqlalchemy.orm import Session

from app.database import get_db
from app.dependencies import get_current_user, log_audit, require_role
from app.models.user import User
from app.schemas.alert import AlertCreate, AlertResponse, AlertStats, AlertUpdate
from app.services import alert_service

router = APIRouter(prefix="/api/v1/alerts", tags=["Alertes"])

_admin = require_role("DIRECTION", "ADMIN_TECH")
_field = require_role("DIRECTION", "ADMIN_TECH", "TEACHER")


@router.post("", response_model=AlertResponse, status_code=201, summary="Creer une alerte (US 4.3)")
def create_alert(
    data: AlertCreate,
    request: Request,
    current_user: User = Depends(_field),
    db: Session = Depends(get_db),
):
    """
    Cree une alerte (eleve manquant, retard, etc.).
    Accessible aux enseignants et a la direction.
    """
    try:
        alert = alert_service.create_alert(db, data, created_by=current_user.id)
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))

    log_audit(
        db, user_id=current_user.id, action="ALERT_CREATED",
        resource_type="ALERT", resource_id=None,
        ip_address=request.client.host if request.client else None,
        user_agent=request.headers.get("user-agent"),
        details={
            "alert_id": str(alert.id),
            "alert_type": data.alert_type,
            "severity": data.severity,
            "student_id": str(data.student_id),
        },
    )

    return alert


@router.get("", response_model=List[AlertResponse], summary="Lister les alertes")
def list_alerts(
    trip_id: Optional[str] = Query(None, description="Filtrer par voyage"),
    status: Optional[str] = Query(None, description="Filtrer par statut (ACTIVE, IN_PROGRESS, RESOLVED, ALL)"),
    current_user: User = Depends(_admin),
    db: Session = Depends(get_db),
):
    """Retourne les alertes avec filtres optionnels."""
    tid = None
    if trip_id:
        try:
            tid = uuid.UUID(trip_id)
        except ValueError:
            raise HTTPException(status_code=400, detail="trip_id invalide.")

    return alert_service.get_alerts(db, trip_id=tid, status_filter=status)


@router.get("/active", response_model=List[AlertResponse], summary="Alertes actives")
def get_active_alerts(
    trip_id: Optional[str] = Query(None, description="Filtrer par voyage"),
    current_user: User = Depends(_admin),
    db: Session = Depends(get_db),
):
    """Retourne uniquement les alertes ACTIVE et IN_PROGRESS (pour polling dashboard)."""
    tid = None
    if trip_id:
        try:
            tid = uuid.UUID(trip_id)
        except ValueError:
            raise HTTPException(status_code=400, detail="trip_id invalide.")

    return alert_service.get_active_alerts(db, trip_id=tid)


@router.get("/stats", response_model=AlertStats, summary="Statistiques alertes")
def get_alert_stats(
    trip_id: Optional[str] = Query(None, description="Filtrer par voyage"),
    current_user: User = Depends(_admin),
    db: Session = Depends(get_db),
):
    """Retourne les compteurs d'alertes (total, active, en cours, resolues, critiques)."""
    tid = None
    if trip_id:
        try:
            tid = uuid.UUID(trip_id)
        except ValueError:
            raise HTTPException(status_code=400, detail="trip_id invalide.")

    return alert_service.get_alert_stats(db, trip_id=tid)


@router.patch("/{alert_id}", response_model=AlertResponse, summary="Traiter/Resoudre une alerte")
def update_alert(
    alert_id: uuid.UUID,
    data: AlertUpdate,
    request: Request,
    current_user: User = Depends(_admin),
    db: Session = Depends(get_db),
):
    """
    Met a jour le statut d'une alerte :
    - IN_PROGRESS : alerte prise en charge
    - RESOLVED : alerte resolue
    """
    try:
        alert = alert_service.update_alert_status(
            db, alert_id, data, resolved_by=current_user.id
        )
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))

    action = "ALERT_RESOLVED" if data.status == "RESOLVED" else "ALERT_ACKNOWLEDGED"

    log_audit(
        db, user_id=current_user.id, action=action,
        resource_type="ALERT", resource_id=None,
        ip_address=request.client.host if request.client else None,
        user_agent=request.headers.get("user-agent"),
        details={"alert_id": str(alert_id), "new_status": data.status},
    )

    return alert
