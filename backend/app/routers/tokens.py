"""
Router pour les assignations de bracelets (US 1.5, US 6.2, US 6.3).
Ecriture (assign/reassign/release) : DIRECTION, ADMIN_TECH.
Lecture (statut, liste, export) : tous les utilisateurs authentifies.
Export CSV : optionnellement protege par mot de passe ZIP AES-256 (US 6.3).
"""

import io
import uuid
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import StreamingResponse
from sqlalchemy.orm import Session

from app.database import get_db
from app.dependencies import get_current_user, require_role
from app.models.user import User
from app.schemas.assignment import (
    AssignmentCreate,
    AssignmentReassign,
    AssignmentResponse,
    TripAssignmentStatus,
    TripStudentsResponse,
)
from app.services import assignment_service

router = APIRouter(prefix="/api/v1", tags=["Assignations bracelets"])

_admin = require_role("DIRECTION", "ADMIN_TECH")


@router.post("/tokens/assign", response_model=AssignmentResponse, status_code=201,
             summary="Assigner un bracelet à un élève")
def assign_token(
    data: AssignmentCreate,
    current_user: User = Depends(_admin),
    db: Session = Depends(get_db),
):
    """
    Assigne un bracelet NFC ou QR physique à un élève pour un voyage spécifique.
    """
    try:
        return assignment_service.assign_token(db, data)
    except ValueError as e:
        raise HTTPException(status_code=409, detail=str(e))


@router.post("/tokens/reassign", response_model=AssignmentResponse, status_code=201,
             summary="Réassigner un bracelet")
def reassign_token(
    data: AssignmentReassign,
    current_user: User = Depends(_admin),
    db: Session = Depends(get_db),
):
    """
    Réassigne un bracelet en cas d'erreur.
    Libère les assignations actives précédentes et en crée une nouvelle.
    """
    try:
        return assignment_service.reassign_token(db, data)
    except ValueError as e:
        raise HTTPException(status_code=409, detail=str(e))


@router.get("/trips/{trip_id}/assignments", response_model=TripAssignmentStatus,
            summary="Statut des assignations d'un voyage")
def get_trip_assignments(
    trip_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Retourne le statut des assignations pour un voyage.
    """
    return assignment_service.get_trip_assignment_status(db, trip_id)


@router.get(
    "/trips/{trip_id}/students",
    response_model=TripStudentsResponse,
    summary="Élèves du voyage avec statut d'assignation",
)
def get_trip_students(
    trip_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Retourne la liste des élèves inscrits au voyage avec leur bracelet actif (si assigné).
    """
    return assignment_service.get_trip_students_with_assignments(db, trip_id)


@router.post(
    "/trips/{trip_id}/release-tokens",
    status_code=200,
    summary="Libérer manuellement tous les bracelets d'un voyage",
)
def release_trip_tokens(
    trip_id: uuid.UUID,
    current_user: User = Depends(_admin),
    db: Session = Depends(get_db),
):
    """
    Libère toutes les assignations actives d'un voyage (released_at = NOW()).
    """
    count = assignment_service.release_trip_tokens(db, trip_id)
    return {"trip_id": str(trip_id), "released_count": count}


@router.get("/trips/{trip_id}/assignments/export",
            summary="Exporter les assignations en CSV")
def export_assignments(
    trip_id: uuid.UUID,
    password: Optional[str] = Query(None, description="Mot de passe pour chiffrement ZIP AES-256 (optionnel)"),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Exporte la liste des assignations actives d'un voyage.
    Sans mot de passe : CSV brut. Avec mot de passe : ZIP AES-256 (US 6.3).
    """
    csv_content = assignment_service.export_assignments_csv(db, trip_id)

    if password:
        import pyzipper
        zip_buffer = io.BytesIO()
        with pyzipper.AESZipFile(
            zip_buffer, "w",
            compression=pyzipper.ZIP_DEFLATED,
            encryption=pyzipper.WZ_AES,
        ) as zf:
            zf.setpassword(password.encode("utf-8"))
            zf.writestr(f"assignations_{trip_id}.csv", csv_content.encode("utf-8"))
        zip_buffer.seek(0)
        return StreamingResponse(
            zip_buffer,
            media_type="application/zip",
            headers={"Content-Disposition": f"attachment; filename=assignations_{trip_id}.zip"},
        )

    return StreamingResponse(
        iter([csv_content]),
        media_type="text/csv; charset=utf-8",
        headers={"Content-Disposition": f"attachment; filename=assignations_{trip_id}.csv"},
    )
