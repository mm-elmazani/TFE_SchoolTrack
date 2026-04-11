"""
Router pour les tokens (US 1.4) et assignations de bracelets (US 1.5, US 6.2, US 6.3, US 6.4).
Ecriture (init/assign/reassign/release) : DIRECTION, ADMIN_TECH.
Lecture (statut, liste, export, stock) : tous les utilisateurs authentifies.
Export CSV : optionnellement protege par mot de passe ZIP AES-256 (US 6.3).
Audit logging sur toutes les actions d'ecriture et exports.
"""

import io
import uuid
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from fastapi.responses import StreamingResponse
from sqlalchemy.orm import Session

from app.database import get_db
from app.dependencies import get_client_ip, get_current_user, log_audit, require_role
from app.models.user import User
from app.schemas.assignment import (
    AssignmentCreate,
    AssignmentReassign,
    AssignmentResponse,
    TokenBatchCreate,
    TokenCreate,
    TokenResponse,
    TokenStatsResponse,
    TokenStatusUpdate,
    TripAssignmentStatus,
    TripStudentsResponse,
)
from app.services import assignment_service

router = APIRouter(prefix="/api/v1", tags=["Tokens & Assignations"])

_admin = require_role("DIRECTION", "ADMIN_TECH")


# ----------------------------------------------------------------
# US 1.4 — Initialisation du stock de bracelets
# ----------------------------------------------------------------


@router.post("/tokens/init", response_model=TokenResponse, status_code=201,
             summary="Enregistrer un token dans le stock")
def init_token(
    data: TokenCreate,
    request: Request,
    current_user: User = Depends(_admin),
    db: Session = Depends(get_db),
):
    """
    Enregistre un token unique (bracelet NFC ou QR physique) dans le stock
    avec le statut AVAILABLE. Utilise apres l'encodage NFC sur le terrain.
    """
    try:
        result = assignment_service.init_token(db, data, school_id=current_user.school_id)
    except ValueError as e:
        raise HTTPException(status_code=409, detail=str(e))

    log_audit(
        db, user_id=current_user.id, action="TOKEN_INITIALIZED",
        resource_type="TOKEN", resource_id=None,
        ip_address=get_client_ip(request),
        user_agent=request.headers.get("user-agent"),
        details={"token_id": result.id, "token_uid": data.token_uid, "token_type": data.token_type},
    )

    return result


@router.post("/tokens/init-batch", response_model=List[TokenResponse], status_code=201,
             summary="Enregistrer un lot de tokens dans le stock")
def init_tokens_batch(
    data: TokenBatchCreate,
    request: Request,
    current_user: User = Depends(_admin),
    db: Session = Depends(get_db),
):
    """
    Enregistre un lot de tokens en une seule requete.
    Utile pour l'initialisation en serie (ST-001 a ST-100).
    """
    try:
        results = assignment_service.init_tokens_batch(db, data, school_id=current_user.school_id)
    except ValueError as e:
        raise HTTPException(status_code=409, detail=str(e))

    log_audit(
        db, user_id=current_user.id, action="TOKENS_BATCH_INITIALIZED",
        resource_type="TOKEN", resource_id=None,
        ip_address=get_client_ip(request),
        user_agent=request.headers.get("user-agent"),
        details={"count": len(results), "uids": [r.token_uid for r in results]},
    )

    return results


@router.get("/tokens", response_model=List[TokenResponse],
            summary="Lister les tokens du stock")
def list_tokens(
    status: Optional[str] = Query(None, description="Filtrer par statut (AVAILABLE, ASSIGNED, DAMAGED, LOST)"),
    token_type: Optional[str] = Query(None, description="Filtrer par type (NFC_PHYSICAL, QR_PHYSICAL)"),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Retourne la liste des tokens du stock avec filtres optionnels.
    """
    return assignment_service.list_tokens(db, school_id=current_user.school_id, status=status, token_type=token_type)


@router.get("/tokens/stats", response_model=TokenStatsResponse,
            summary="Statistiques du stock de tokens")
def get_token_stats(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Retourne les compteurs du stock : total, disponibles, assignes, endommages, perdus.
    """
    return assignment_service.get_token_stats(db, school_id=current_user.school_id)


@router.get("/tokens/next-sequence",
            summary="Prochain numero de sequence disponible pour un prefixe")
def get_next_sequence(
    prefix: str = Query("ST", description="Prefixe du token_uid (ex: ST)"),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Retourne le prochain numero de sequence disponible pour le prefixe donne.
    Exemple : si le dernier token est ST-042, retourne {"next_sequence": 43}.
    """
    return assignment_service.get_next_sequence(db, prefix, school_id=current_user.school_id)


@router.get("/tokens/{token_id}/assignment-info",
            summary="Info assignation active d'un token")
def get_token_assignment_info(
    token_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Retourne les details de l'assignation active (eleve + voyage) si le token est assigne.
    Retourne null si pas d'assignation active.
    """
    info = assignment_service.get_token_assignment_info(db, token_id, school_id=current_user.school_id)
    return info or {"assignment_id": None}


@router.delete("/tokens/{token_id}", status_code=204,
               summary="Supprimer un token du stock")
def delete_token(
    token_id: int,
    request: Request,
    current_user: User = Depends(_admin),
    db: Session = Depends(get_db),
):
    """
    Supprime un token du stock. Interdit si le token est actuellement ASSIGNED.
    """
    try:
        assignment_service.delete_token(db, token_id, school_id=current_user.school_id)
    except ValueError as e:
        status = 404 if "introuvable" in str(e) else 409
        raise HTTPException(status_code=status, detail=str(e))

    log_audit(
        db, user_id=current_user.id, action="TOKEN_DELETED",
        resource_type="TOKEN", resource_id=None,
        ip_address=get_client_ip(request),
        user_agent=request.headers.get("user-agent"),
        details={"token_id": token_id},
    )


@router.patch("/tokens/{token_id}/status", response_model=TokenResponse,
              summary="Modifier le statut d'un token")
def update_token_status(
    token_id: int,
    data: TokenStatusUpdate,
    request: Request,
    current_user: User = Depends(_admin),
    db: Session = Depends(get_db),
):
    """
    Met a jour le statut d'un token (ex: DAMAGED, LOST, AVAILABLE).
    """
    try:
        result = assignment_service.update_token_status_by_id(db, token_id, data.status, school_id=current_user.school_id)
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))

    log_audit(
        db, user_id=current_user.id, action="TOKEN_STATUS_UPDATED",
        resource_type="TOKEN", resource_id=None,
        ip_address=get_client_ip(request),
        user_agent=request.headers.get("user-agent"),
        details={"token_id": token_id, "token_uid": result.token_uid, "new_status": data.status},
    )

    return result


# ----------------------------------------------------------------
# US 1.5 — Assignation des bracelets
# ----------------------------------------------------------------


@router.post("/tokens/assign", response_model=AssignmentResponse, status_code=201,
             summary="Assigner un bracelet à un élève")
def assign_token(
    data: AssignmentCreate,
    request: Request,
    current_user: User = Depends(_admin),
    db: Session = Depends(get_db),
):
    """
    Assigne un bracelet NFC ou QR physique à un élève pour un voyage spécifique.
    """
    try:
        result = assignment_service.assign_token(db, data)
    except ValueError as e:
        raise HTTPException(status_code=409, detail=str(e))

    log_audit(
        db, user_id=current_user.id, action="TOKEN_ASSIGNED",
        resource_type="ASSIGNMENT", resource_id=None,
        ip_address=get_client_ip(request),
        user_agent=request.headers.get("user-agent"),
        details={"assignment_id": result.id, "student_id": str(data.student_id), "trip_id": str(data.trip_id)},
    )

    return result


@router.post("/tokens/reassign", response_model=AssignmentResponse, status_code=201,
             summary="Réassigner un bracelet")
def reassign_token(
    data: AssignmentReassign,
    request: Request,
    current_user: User = Depends(_admin),
    db: Session = Depends(get_db),
):
    """
    Réassigne un bracelet en cas d'erreur.
    Libère les assignations actives précédentes et en crée une nouvelle.
    """
    try:
        result = assignment_service.reassign_token(db, data)
    except ValueError as e:
        raise HTTPException(status_code=409, detail=str(e))

    log_audit(
        db, user_id=current_user.id, action="TOKEN_REASSIGNED",
        resource_type="ASSIGNMENT", resource_id=None,
        ip_address=get_client_ip(request),
        user_agent=request.headers.get("user-agent"),
        details={"assignment_id": result.id, "student_id": str(data.student_id), "trip_id": str(data.trip_id)},
    )

    return result


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
    request: Request,
    current_user: User = Depends(_admin),
    db: Session = Depends(get_db),
):
    """
    Libère toutes les assignations actives d'un voyage (released_at = NOW()).
    """
    count = assignment_service.release_trip_tokens(db, trip_id)

    log_audit(
        db, user_id=current_user.id, action="TOKENS_RELEASED",
        resource_type="TRIP", resource_id=trip_id,
        ip_address=get_client_ip(request),
        user_agent=request.headers.get("user-agent"),
        details={"released_count": count},
    )

    return {"trip_id": str(trip_id), "released_count": count}


@router.post(
    "/assignments/{assignment_id}/release",
    status_code=200,
    summary="Desassigner un bracelet individuel",
)
def release_assignment(
    assignment_id: int,
    request: Request,
    current_user: User = Depends(_admin),
    db: Session = Depends(get_db),
):
    """
    Libere une assignation individuelle (released_at = NOW()).
    Remet le token physique en AVAILABLE.
    """
    try:
        result = assignment_service.release_assignment(db, assignment_id)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))

    log_audit(
        db, user_id=current_user.id, action="TOKEN_RELEASED",
        resource_type="ASSIGNMENT", resource_id=None,
        ip_address=get_client_ip(request),
        user_agent=request.headers.get("user-agent"),
        details=result,
    )

    return result


@router.get("/trips/{trip_id}/assignments/export",
            summary="Exporter les assignations en CSV")
def export_assignments(
    trip_id: uuid.UUID,
    request: Request,
    password: Optional[str] = Query(None, description="Mot de passe pour chiffrement ZIP AES-256 (optionnel)"),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Exporte la liste des assignations actives d'un voyage.
    Sans mot de passe : CSV brut. Avec mot de passe : ZIP AES-256 (US 6.3).
    """
    csv_content = assignment_service.export_assignments_csv(db, trip_id)

    log_audit(
        db, user_id=current_user.id, action="ASSIGNMENTS_EXPORTED",
        resource_type="TRIP", resource_id=trip_id,
        ip_address=get_client_ip(request),
        user_agent=request.headers.get("user-agent"),
        details={"format": "zip_aes256" if password else "csv"},
    )

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
