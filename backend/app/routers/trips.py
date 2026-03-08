"""
Router pour les voyages (US 1.2, US 1.6, US 2.1, US 6.2, US 6.4).
Lecture : tous les utilisateurs authentifies.
Ecriture : DIRECTION et ADMIN_TECH.
Offline data : DIRECTION, ADMIN_TECH, TEACHER.
Audit logging sur toutes les actions d'ecriture.
"""

import uuid
from typing import List

from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.orm import Session

from app.database import get_db
from app.dependencies import get_current_user, log_audit, require_role
from app.models.user import User
from app.schemas.offline import OfflineDataBundle
from app.schemas.qr_email import QrEmailSendResult
from app.schemas.trip import TripCreate, TripResponse, TripUpdate
from app.services import offline_service, qr_email_service, trip_service

router = APIRouter(prefix="/api/v1/trips", tags=["Voyages"])

_admin = require_role("DIRECTION", "ADMIN_TECH")
_field = require_role("DIRECTION", "ADMIN_TECH", "TEACHER")


@router.post("", response_model=TripResponse, status_code=201, summary="Créer un voyage")
def create_trip(
    data: TripCreate,
    request: Request,
    current_user: User = Depends(_admin),
    db: Session = Depends(get_db),
):
    """
    Crée un nouveau voyage scolaire.
    Associe automatiquement les élèves des classes sélectionnées.
    La date doit être dans le futur et au moins une classe doit être fournie.
    """
    trip = trip_service.create_trip(db, data)

    log_audit(
        db, user_id=current_user.id, action="TRIP_CREATED",
        resource_type="TRIP", resource_id=trip.id,
        ip_address=request.client.host if request.client else None,
        user_agent=request.headers.get("user-agent"),
        details={"destination": data.destination},
    )

    return trip


@router.get("", response_model=List[TripResponse], summary="Lister les voyages")
def list_trips(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Retourne tous les voyages actifs (hors archivés), du plus récent au plus ancien."""
    return trip_service.get_trips(db)


@router.get("/{trip_id}", response_model=TripResponse, summary="Détail d'un voyage")
def get_trip(
    trip_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Retourne le détail d'un voyage par son ID."""
    trip = trip_service.get_trip(db, trip_id)
    if trip is None:
        raise HTTPException(status_code=404, detail="Voyage introuvable.")
    return trip


@router.put("/{trip_id}", response_model=TripResponse, summary="Modifier un voyage")
def update_trip(
    trip_id: uuid.UUID,
    data: TripUpdate,
    request: Request,
    current_user: User = Depends(_admin),
    db: Session = Depends(get_db),
):
    """
    Met à jour les informations d'un voyage.
    Seuls les champs fournis sont modifiés.
    """
    trip = trip_service.update_trip(db, trip_id, data)
    if trip is None:
        raise HTTPException(status_code=404, detail="Voyage introuvable.")

    log_audit(
        db, user_id=current_user.id, action="TRIP_UPDATED",
        resource_type="TRIP", resource_id=trip.id,
        ip_address=request.client.host if request.client else None,
        user_agent=request.headers.get("user-agent"),
        details={"fields": list(data.model_dump(exclude_unset=True).keys())},
    )

    return trip


@router.delete("/{trip_id}", status_code=204, summary="Archiver un voyage")
def archive_trip(
    trip_id: uuid.UUID,
    request: Request,
    current_user: User = Depends(_admin),
    db: Session = Depends(get_db),
):
    """
    Archive un voyage (suppression logique — status → ARCHIVED).
    Les données sont conservées pour l'historique.
    """
    success = trip_service.archive_trip(db, trip_id)
    if not success:
        raise HTTPException(status_code=404, detail="Voyage introuvable.")

    log_audit(
        db, user_id=current_user.id, action="TRIP_ARCHIVED",
        resource_type="TRIP", resource_id=trip_id,
        ip_address=request.client.host if request.client else None,
        user_agent=request.headers.get("user-agent"),
    )


@router.get(
    "/{trip_id}/offline-data",
    response_model=OfflineDataBundle,
    summary="Télécharger le bundle offline d'un voyage (US 2.1)",
)
def get_offline_data(
    trip_id: uuid.UUID,
    current_user: User = Depends(_field),
    db: Session = Depends(get_db),
):
    """
    Retourne le bundle complet de données nécessaire au mode offline de l'app Flutter.
    """
    try:
        return offline_service.get_offline_data(db, trip_id)
    except ValueError as e:
        msg = str(e)
        if "introuvable" in msg:
            raise HTTPException(status_code=404, detail=msg)
        raise HTTPException(status_code=400, detail=msg)


@router.post(
    "/{trip_id}/send-qr-emails",
    response_model=QrEmailSendResult,
    summary="Envoyer les QR codes digitaux par email (US 1.6)",
)
def send_qr_emails(
    trip_id: uuid.UUID,
    request: Request,
    current_user: User = Depends(_admin),
    db: Session = Depends(get_db),
):
    """
    Envoie les QR codes digitaux par email à tous les élèves inscrits au voyage.
    """
    try:
        result = qr_email_service.send_qr_emails_for_trip(db, trip_id)
    except ValueError as e:
        msg = str(e)
        if "introuvable" in msg:
            raise HTTPException(status_code=404, detail=msg)
        raise HTTPException(status_code=400, detail=msg)

    log_audit(
        db, user_id=current_user.id, action="QR_EMAILS_SENT",
        resource_type="TRIP", resource_id=trip_id,
        ip_address=request.client.host if request.client else None,
        user_agent=request.headers.get("user-agent"),
        details={"sent": result.sent_count, "errors": len(result.errors)},
    )

    return result
