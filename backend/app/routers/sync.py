"""
Router pour la synchronisation offline → online (US 3.1, US 6.2, US 6.4).
Reçoit les scans de présence depuis l'app Flutter et les insère avec idempotence.
Acces reserve aux enseignants et direction.
Audit logging sur chaque synchronisation.
"""

from fastapi import APIRouter, Depends, Request
from sqlalchemy.orm import Session

from app.database import get_db
from app.dependencies import log_audit, require_role
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
    request: Request,
    current_user: User = Depends(_field),
    db: Session = Depends(get_db),
):
    """
    Reçoit un batch de scans générés hors-ligne par l'app Flutter et les insère en base.
    """
    result = sync_service.sync_attendances(db, data.scans, data.device_id)

    log_audit(
        db, user_id=current_user.id, action="SYNC_ATTENDANCES",
        resource_type="ATTENDANCE",
        ip_address=request.client.host if request.client else None,
        user_agent=request.headers.get("user-agent"),
        details={"device_id": data.device_id, "scans_count": len(data.scans),
                 "inserted": result.total_inserted, "duplicates": len(result.duplicate)},
    )

    return result
