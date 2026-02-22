"""
Router pour les assignations de bracelets (US 1.5).
"""

import uuid
from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import StreamingResponse
from sqlalchemy.orm import Session

from app.database import get_db
from app.schemas.assignment import (
    AssignmentCreate,
    AssignmentReassign,
    AssignmentResponse,
    TripAssignmentStatus,
    TripStudentsResponse,
)
from app.services import assignment_service

router = APIRouter(prefix="/api/v1", tags=["Assignations bracelets"])


@router.post("/tokens/assign", response_model=AssignmentResponse, status_code=201,
             summary="Assigner un bracelet à un élève")
def assign_token(data: AssignmentCreate, db: Session = Depends(get_db)):
    """
    Assigne un bracelet NFC ou QR physique à un élève pour un voyage spécifique.

    Contraintes :
    - L'élève doit être inscrit au voyage
    - 1 bracelet = 1 élève par voyage
    - 1 élève = 1 bracelet par voyage
    """
    try:
        return assignment_service.assign_token(db, data)
    except ValueError as e:
        raise HTTPException(status_code=409, detail=str(e))


@router.post("/tokens/reassign", response_model=AssignmentResponse, status_code=201,
             summary="Réassigner un bracelet")
def reassign_token(data: AssignmentReassign, db: Session = Depends(get_db)):
    """
    Réassigne un bracelet en cas d'erreur.
    Libère les assignations actives précédentes et en crée une nouvelle.
    Une justification est obligatoire.
    """
    try:
        return assignment_service.reassign_token(db, data)
    except ValueError as e:
        raise HTTPException(status_code=409, detail=str(e))


@router.get("/trips/{trip_id}/assignments", response_model=TripAssignmentStatus,
            summary="Statut des assignations d'un voyage")
def get_trip_assignments(trip_id: uuid.UUID, db: Session = Depends(get_db)):
    """
    Retourne le statut des assignations pour un voyage :
    nombre d'élèves assignés, non assignés, et la liste complète.
    """
    return assignment_service.get_trip_assignment_status(db, trip_id)


@router.get(
    "/trips/{trip_id}/students",
    response_model=TripStudentsResponse,
    summary="Élèves du voyage avec statut d'assignation",
)
def get_trip_students(trip_id: uuid.UUID, db: Session = Depends(get_db)):
    """
    Retourne la liste des élèves inscrits au voyage avec leur bracelet actif (si assigné).
    Utilisé par le dashboard web pour la gestion des assignations (US 1.5).
    """
    return assignment_service.get_trip_students_with_assignments(db, trip_id)


@router.post(
    "/trips/{trip_id}/release-tokens",
    status_code=200,
    summary="Libérer manuellement tous les bracelets d'un voyage",
)
def release_trip_tokens(trip_id: uuid.UUID, db: Session = Depends(get_db)):
    """
    Libère toutes les assignations actives d'un voyage (released_at = NOW()).

    Cas d'usage : libérer les bracelets sans changer le statut du voyage
    (ex. récupération anticipée des bracelets, erreur d'assignation en masse).
    Pour un voyage terminé normalement, préférer PUT /trips/{id} avec status=COMPLETED.

    Retourne le nombre d'assignations libérées.
    """
    count = assignment_service.release_trip_tokens(db, trip_id)
    return {"trip_id": str(trip_id), "released_count": count}


@router.get("/trips/{trip_id}/assignments/export",
            summary="Exporter les assignations en CSV")
def export_assignments(trip_id: uuid.UUID, db: Session = Depends(get_db)):
    """
    Exporte la liste des assignations actives d'un voyage en CSV (UTF-8 BOM, séparateur ;).
    Compatible Excel.
    """
    csv_content = assignment_service.export_assignments_csv(db, trip_id)

    return StreamingResponse(
        iter([csv_content]),
        media_type="text/csv; charset=utf-8",
        headers={"Content-Disposition": f"attachment; filename=assignations_{trip_id}.csv"}
    )
