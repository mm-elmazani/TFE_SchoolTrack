"""
Routers pour les checkpoints terrain (US 2.5, US 2.7, US 6.2, US 6.4).
Création et clôture par les enseignants / direction depuis l'app mobile.
Audit logging sur creation et cloture.
"""

import uuid

from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.orm import Session

from app.database import get_db
from app.dependencies import log_audit, require_role
from app.models.user import User
from app.schemas.checkpoint import CheckpointCreate, CheckpointResponse, CheckpointsSummary
from app.services import checkpoint_service

# POST /api/v1/trips/{trip_id}/checkpoints (US 2.5)
router = APIRouter(prefix="/api/v1/trips", tags=["Checkpoints"])

# POST /api/v1/checkpoints/{checkpoint_id}/close (US 2.7)
checkpoints_router = APIRouter(prefix="/api/v1/checkpoints", tags=["Checkpoints"])

_field = require_role("DIRECTION", "ADMIN_TECH", "TEACHER")
_admin = require_role("DIRECTION", "ADMIN_TECH")


# ---------------------------------------------------------------------------
# US 4.4 — Timeline / résumé checkpoints (direction uniquement)
# ---------------------------------------------------------------------------


@router.get(
    "/{trip_id}/checkpoints-summary",
    response_model=CheckpointsSummary,
    summary="Résumé et timeline des checkpoints d'un voyage (US 4.4)",
)
def get_checkpoints_summary(
    trip_id: uuid.UUID,
    current_user: User = Depends(_admin),
    db: Session = Depends(get_db),
):
    """
    Retourne le résumé des checkpoints avec timeline, statistiques de scan
    et durées. Réservé à la direction.
    """
    try:
        return checkpoint_service.get_checkpoints_summary(db, trip_id)
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))


@router.post(
    "/{trip_id}/checkpoints",
    response_model=CheckpointResponse,
    status_code=201,
    summary="Créer un checkpoint terrain (US 2.5)",
)
def create_checkpoint(
    trip_id: uuid.UUID,
    data: CheckpointCreate,
    request: Request,
    current_user: User = Depends(_field),
    db: Session = Depends(get_db),
):
    """
    Crée un nouveau checkpoint en statut DRAFT pour le voyage spécifié.
    Retourne 404 si le voyage est introuvable, 400 si le voyage est terminé.
    """
    try:
        result = checkpoint_service.create_checkpoint(db, trip_id, data)
    except ValueError as e:
        msg = str(e)
        if "introuvable" in msg:
            raise HTTPException(status_code=404, detail=msg)
        raise HTTPException(status_code=400, detail=msg)

    log_audit(
        db, user_id=current_user.id, action="CHECKPOINT_CREATED",
        resource_type="CHECKPOINT", resource_id=result.id,
        ip_address=request.client.host if request.client else None,
        user_agent=request.headers.get("user-agent"),
        details={"trip_id": str(trip_id), "name": data.name},
    )

    return result


@checkpoints_router.post(
    "/{checkpoint_id}/close",
    response_model=CheckpointResponse,
    summary="Clôturer un checkpoint (US 2.7)",
)
def close_checkpoint(
    checkpoint_id: uuid.UUID,
    request: Request,
    current_user: User = Depends(_field),
    db: Session = Depends(get_db),
):
    """
    Clôture un checkpoint ACTIVE → CLOSED.
    Retourne 404 si le checkpoint est introuvable,
    400 si le checkpoint est en statut DRAFT ou déjà CLOSED.
    """
    try:
        result = checkpoint_service.close_checkpoint(db, checkpoint_id)
    except ValueError as e:
        msg = str(e)
        if "introuvable" in msg:
            raise HTTPException(status_code=404, detail=msg)
        raise HTTPException(status_code=400, detail=msg)

    log_audit(
        db, user_id=current_user.id, action="CHECKPOINT_CLOSED",
        resource_type="CHECKPOINT", resource_id=checkpoint_id,
        ip_address=request.client.host if request.client else None,
        user_agent=request.headers.get("user-agent"),
    )

    return result
