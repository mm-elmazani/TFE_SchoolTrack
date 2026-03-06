"""
Router pour la synchronisation offline → online (US 3.1, US 6.2).
Reçoit les scans de présence depuis l'app Flutter et les insère avec idempotence.
Acces reserve aux enseignants et direction.
"""

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.database import get_db
from app.dependencies import require_role
from app.models.user import User
from app.schemas.sync import SyncRequest, SyncResponse
from app.services import sync_service

router = APIRouter(prefix="/api/sync", tags=["Synchronisation offline"])

_field = require_role("DIRECTION", "ADMIN_TECH", "TEACHER")


@router.post(
    "/attendances",
    response_model=SyncResponse,
    summary="Synchroniser les scans de présence (offline → online)",
)
def sync_attendances(
    data: SyncRequest,
    current_user: User = Depends(_field),
    db: Session = Depends(get_db),
):
    """
    Reçoit un batch de scans générés hors-ligne par l'app Flutter et les insère en base.
    """
    return sync_service.sync_attendances(db, data.scans, data.device_id)
