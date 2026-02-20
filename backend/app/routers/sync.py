"""
Router pour la synchronisation offline → online (US 3.1).
Reçoit les scans de présence depuis l'app Flutter et les insère avec idempotence.
"""

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.database import get_db
from app.schemas.sync import SyncRequest, SyncResponse
from app.services import sync_service

router = APIRouter(prefix="/api/sync", tags=["Synchronisation offline"])


@router.post(
    "/attendances",
    response_model=SyncResponse,
    summary="Synchroniser les scans de présence (offline → online)",
)
def sync_attendances(data: SyncRequest, db: Session = Depends(get_db)):
    """
    Reçoit un batch de scans générés hors-ligne par l'app Flutter et les insère en base.

    Comportement :
    - Idempotent : un client_uuid déjà connu est ignoré (pas d'erreur)
    - Append-only : 2 scans différents sur le même élève/checkpoint coexistent (UUIDs distincts)
    - Doublons intra-batch et inter-batch gérés séparément
    - Retourne le rapport : UUIDs acceptés / doublons / totaux

    Utilisé par le Dart Isolate de l'app Flutter dès reconnexion réseau.
    """
    return sync_service.sync_attendances(db, data.scans, data.device_id)
