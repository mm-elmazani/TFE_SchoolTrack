"""
Router pour la consultation et l'export des logs d'audit (US 6.4).
Acces reserve a DIRECTION et ADMIN_TECH.
Filtres : utilisateur, action, date, type de ressource.
Pagination incluse. Export JSON pour audit externe.
"""

import json
import math
from datetime import date, datetime, time
from typing import Optional

from fastapi import APIRouter, Depends, Query, Request
from fastapi.responses import StreamingResponse
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.database import get_db
from app.dependencies import get_client_ip, log_audit, require_role
from app.models.user import User
from app.schemas.audit import AuditLogPage, AuditLogResponse

router = APIRouter(prefix="/api/v1/audit", tags=["Audit"])

_admin = require_role("DIRECTION", "ADMIN_TECH")


# ── Helper : construction des filtres SQL ────────────────────────────────

def _build_where(
    user_id: Optional[str],
    action: Optional[str],
    resource_type: Optional[str],
    date_from: Optional[date],
    date_to: Optional[date],
    current_user: Optional[User] = None,
) -> tuple[str, dict]:
    """Retourne (where_sql, params) a partir des filtres optionnels.
    Isolation multi-tenant US 6.6 : tous les roles (y compris ADMIN_TECH)
    sont scope a l'ecole de leur JWT. Acces global uniquement via SSH+psql."""
    clauses: list[str] = []
    params: dict = {}

    # Isolation par ecole pour tous les roles authentifies.
    if current_user is not None:
        clauses.append("u.school_id = :school_id")
        params["school_id"] = str(current_user.school_id)

    if user_id:
        clauses.append("a.user_id = :user_id")
        params["user_id"] = user_id
    if action:
        clauses.append("a.action = :action")
        params["action"] = action
    if resource_type:
        clauses.append("a.resource_type = :resource_type")
        params["resource_type"] = resource_type
    if date_from:
        clauses.append("a.performed_at >= :date_from")
        params["date_from"] = datetime.combine(date_from, time.min)
    if date_to:
        clauses.append("a.performed_at <= :date_to")
        params["date_to"] = datetime.combine(date_to, time.max)

    where_sql = (" AND ".join(clauses)) if clauses else "1=1"
    return where_sql, params


def _row_to_response(row) -> AuditLogResponse:
    return AuditLogResponse(
        id=row[0],
        user_id=row[1],
        user_email=row[2],
        action=row[3],
        resource_type=row[4],
        resource_id=row[5],
        ip_address=row[6],
        user_agent=row[7],
        details=row[8],
        performed_at=row[9],
    )


# ── GET /logs — consultation paginee ─────────────────────────────────────

@router.get("/logs", response_model=AuditLogPage, summary="Consulter les logs d'audit")
def list_audit_logs(
    page: int = Query(1, ge=1, description="Numero de page"),
    page_size: int = Query(50, ge=1, le=200, description="Nombre d'elements par page"),
    user_id: Optional[str] = Query(None, description="Filtrer par UUID utilisateur"),
    action: Optional[str] = Query(None, description="Filtrer par action (ex: LOGIN_SUCCESS)"),
    resource_type: Optional[str] = Query(None, description="Filtrer par type de ressource (ex: STUDENT, TRIP)"),
    date_from: Optional[date] = Query(None, description="Date de debut (incluse)"),
    date_to: Optional[date] = Query(None, description="Date de fin (incluse)"),
    current_user: User = Depends(_admin),
    db: Session = Depends(get_db),
):
    """
    Retourne les logs d'audit avec filtres optionnels et pagination.
    Les logs sont tries du plus recent au plus ancien.
    Jointure avec la table users pour afficher l'email de l'auteur.
    """
    where_sql, params = _build_where(user_id, action, resource_type, date_from, date_to, current_user)

    # Comptage total
    total = db.execute(
        text(
            f"SELECT COUNT(*) FROM audit_logs a "  # noqa: S608
            f"LEFT JOIN users u ON a.user_id = u.id "
            f"WHERE {where_sql}"
        ),
        params,
    ).scalar()

    # Requete paginee
    offset = (page - 1) * page_size
    params["limit"] = page_size
    params["offset"] = offset

    rows = db.execute(
        text(
            f"SELECT a.id, a.user_id, u.email AS user_email, a.action, "  # noqa: S608
            f"a.resource_type, a.resource_id, a.ip_address::text, a.user_agent, "
            f"a.details, a.performed_at "
            f"FROM audit_logs a "
            f"LEFT JOIN users u ON a.user_id = u.id "
            f"WHERE {where_sql} "
            f"ORDER BY a.performed_at DESC "
            f"LIMIT :limit OFFSET :offset"
        ),
        params,
    ).fetchall()

    items = [_row_to_response(row) for row in rows]
    total_pages = max(1, math.ceil(total / page_size))

    return AuditLogPage(
        items=items,
        total=total,
        page=page,
        page_size=page_size,
        total_pages=total_pages,
    )


# ── GET /logs/export — export JSON pour audit externe ────────────────────

@router.get("/logs/export", summary="Exporter les logs d'audit en JSON")
def export_audit_logs(
    request: Request,
    user_id: Optional[str] = Query(None, description="Filtrer par UUID utilisateur"),
    action: Optional[str] = Query(None, description="Filtrer par action"),
    resource_type: Optional[str] = Query(None, description="Filtrer par type de ressource"),
    date_from: Optional[date] = Query(None, description="Date de debut (incluse)"),
    date_to: Optional[date] = Query(None, description="Date de fin (incluse)"),
    current_user: User = Depends(_admin),
    db: Session = Depends(get_db),
):
    """
    Exporte tous les logs correspondant aux filtres en fichier JSON telechargeable.
    Pas de pagination — retourne l'integralite des resultats filtres.
    Destine aux audits externes (conformite RGPD).
    """
    where_sql, params = _build_where(user_id, action, resource_type, date_from, date_to, current_user)

    rows = db.execute(
        text(
            f"SELECT a.id, a.user_id, u.email AS user_email, a.action, "  # noqa: S608
            f"a.resource_type, a.resource_id, a.ip_address::text, a.user_agent, "
            f"a.details, a.performed_at "
            f"FROM audit_logs a "
            f"LEFT JOIN users u ON a.user_id = u.id "
            f"WHERE {where_sql} "
            f"ORDER BY a.performed_at DESC"
        ),
        params,
    ).fetchall()

    items = [_row_to_response(row) for row in rows]

    # Audit : tracer l'export lui-meme
    log_audit(
        db, user_id=current_user.id, action="AUDIT_LOGS_EXPORTED",
        resource_type="AUDIT",
        ip_address=get_client_ip(request),
        user_agent=request.headers.get("user-agent"),
        details={"filters": {k: str(v) for k, v in params.items()}, "count": len(items)},
    )

    # Serialisation JSON avec dates ISO
    export_data = {
        "exported_at": datetime.utcnow().isoformat(),
        "exported_by": current_user.email,
        "total": len(items),
        "filters": {
            "user_id": user_id,
            "action": action,
            "resource_type": resource_type,
            "date_from": str(date_from) if date_from else None,
            "date_to": str(date_to) if date_to else None,
        },
        "logs": [item.model_dump(mode="json") for item in items],
    }

    json_content = json.dumps(export_data, ensure_ascii=False, indent=2, default=str)

    today = date.today().isoformat()
    return StreamingResponse(
        iter([json_content]),
        media_type="application/json",
        headers={"Content-Disposition": f'attachment; filename="audit_logs_{today}.json"'},
    )
