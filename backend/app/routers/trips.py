"""
Router pour les voyages (US 1.2, US 1.6).
CRUD complet : création, lecture, modification, archivage.
Envoi QR codes par email (US 1.6).
"""

import uuid
from typing import List

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.database import get_db
from app.schemas.qr_email import QrEmailSendResult
from app.schemas.trip import TripCreate, TripResponse, TripUpdate
from app.services import qr_email_service, trip_service

router = APIRouter(prefix="/api/v1/trips", tags=["Voyages"])


@router.post("", response_model=TripResponse, status_code=201, summary="Créer un voyage")
def create_trip(data: TripCreate, db: Session = Depends(get_db)):
    """
    Crée un nouveau voyage scolaire.
    Associe automatiquement les élèves des classes sélectionnées.
    La date doit être dans le futur et au moins une classe doit être fournie.
    """
    return trip_service.create_trip(db, data)


@router.get("", response_model=List[TripResponse], summary="Lister les voyages")
def list_trips(db: Session = Depends(get_db)):
    """Retourne tous les voyages actifs (hors archivés), du plus récent au plus ancien."""
    return trip_service.get_trips(db)


@router.get("/{trip_id}", response_model=TripResponse, summary="Détail d'un voyage")
def get_trip(trip_id: uuid.UUID, db: Session = Depends(get_db)):
    """Retourne le détail d'un voyage par son ID."""
    trip = trip_service.get_trip(db, trip_id)
    if trip is None:
        raise HTTPException(status_code=404, detail="Voyage introuvable.")
    return trip


@router.put("/{trip_id}", response_model=TripResponse, summary="Modifier un voyage")
def update_trip(trip_id: uuid.UUID, data: TripUpdate, db: Session = Depends(get_db)):
    """
    Met à jour les informations d'un voyage.
    Seuls les champs fournis sont modifiés.
    """
    trip = trip_service.update_trip(db, trip_id, data)
    if trip is None:
        raise HTTPException(status_code=404, detail="Voyage introuvable.")
    return trip


@router.delete("/{trip_id}", status_code=204, summary="Archiver un voyage")
def archive_trip(trip_id: uuid.UUID, db: Session = Depends(get_db)):
    """
    Archive un voyage (suppression logique — status → ARCHIVED).
    Les données sont conservées pour l'historique.
    """
    success = trip_service.archive_trip(db, trip_id)
    if not success:
        raise HTTPException(status_code=404, detail="Voyage introuvable.")


@router.post(
    "/{trip_id}/send-qr-emails",
    response_model=QrEmailSendResult,
    summary="Envoyer les QR codes digitaux par email (US 1.6)",
)
def send_qr_emails(trip_id: uuid.UUID, db: Session = Depends(get_db)):
    """
    Envoie les QR codes digitaux par email à tous les élèves inscrits au voyage.

    - Génère un token QR_DIGITAL unique par élève (format : QRD-XXXXXXXX)
    - Skip les élèves sans email (no_email_count)
    - Skip les élèves déjà porteurs d'un QR_DIGITAL actif (already_sent_count)
    - En cas d'erreur SMTP individuelle : continue et log dans errors
    - Retourne un rapport complet (envoyés, déjà envoyés, sans email, erreurs)

    Idempotent : un second appel n'envoie que les élèves non encore notifiés.
    """
    try:
        return qr_email_service.send_qr_emails_for_trip(db, trip_id)
    except ValueError as e:
        msg = str(e)
        if "introuvable" in msg:
            raise HTTPException(status_code=404, detail=msg)
        raise HTTPException(status_code=400, detail=msg)
