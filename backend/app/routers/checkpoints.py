"""
Routers pour les checkpoints terrain (US 2.5 + US 2.7).
Création dynamique et clôture par les enseignants depuis l'app mobile.
"""

import uuid

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.database import get_db
from app.schemas.checkpoint import CheckpointCreate, CheckpointResponse
from app.services import checkpoint_service

# POST /api/v1/trips/{trip_id}/checkpoints (US 2.5)
router = APIRouter(prefix="/api/v1/trips", tags=["Checkpoints"])

# POST /api/v1/checkpoints/{checkpoint_id}/close (US 2.7)
checkpoints_router = APIRouter(prefix="/api/v1/checkpoints", tags=["Checkpoints"])


@router.post(
    "/{trip_id}/checkpoints",
    response_model=CheckpointResponse,
    status_code=201,
    summary="Créer un checkpoint terrain (US 2.5)",
)
def create_checkpoint(
    trip_id: uuid.UUID,
    data: CheckpointCreate,
    db: Session = Depends(get_db),
):
    """
    Crée un nouveau checkpoint en statut DRAFT pour le voyage spécifié.

    L'enseignant appelle cet endpoint depuis l'app mobile quand il crée
    un point de contrôle sur le terrain. Le checkpoint passe automatiquement
    à ACTIVE au premier scan d'élève (géré côté Flutter + sync US 3.1).

    Retourne 404 si le voyage est introuvable, 400 si le voyage est terminé.
    """
    try:
        return checkpoint_service.create_checkpoint(db, trip_id, data)
    except ValueError as e:
        msg = str(e)
        if "introuvable" in msg:
            raise HTTPException(status_code=404, detail=msg)
        raise HTTPException(status_code=400, detail=msg)


@checkpoints_router.post(
    "/{checkpoint_id}/close",
    response_model=CheckpointResponse,
    summary="Clôturer un checkpoint (US 2.7)",
)
def close_checkpoint(
    checkpoint_id: uuid.UUID,
    db: Session = Depends(get_db),
):
    """
    Clôture un checkpoint ACTIVE → CLOSED.

    Marque le checkpoint comme terminé (closed_at = now, status = CLOSED).
    Un checkpoint CLOSED est en lecture seule : aucun nouveau scan n'y est accepté.

    Retourne 404 si le checkpoint est introuvable,
    400 si le checkpoint est en statut DRAFT ou déjà CLOSED.
    """
    try:
        return checkpoint_service.close_checkpoint(db, checkpoint_id)
    except ValueError as e:
        msg = str(e)
        if "introuvable" in msg:
            raise HTTPException(status_code=404, detail=msg)
        raise HTTPException(status_code=400, detail=msg)
