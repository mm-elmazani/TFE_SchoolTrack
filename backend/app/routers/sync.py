"""
Router pour la synchronisation offline → online (US 3.1, US 6.2, US 6.4).
Reçoit les scans de présence depuis l'app Flutter et les insère avec idempotence.
Acces reserve aux enseignants et direction.
Audit logging sur chaque synchronisation.
"""

import math
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.database import get_db
from app.dependencies import get_client_ip, log_audit, require_role
from app.models.sync_log import SyncLog
from app.models.trip import Trip
from app.models.user import User
from app.schemas.sync import (
    SyncLogOut,
    SyncLogPage,
    SyncRequest,
    SyncResponse,
    SyncStats,
)
from app.services import sync_service

router = APIRouter(prefix="/api/sync", tags=["Synchronisation offline"])

_field = require_role("DIRECTION", "ADMIN_TECH", "TEACHER")
_admin = require_role("DIRECTION", "ADMIN_TECH")


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
    try:
        result = sync_service.sync_attendances(
            db, data.scans, data.device_id, scanned_by=current_user.id,
            school_id=current_user.school_id,
        )
    except ValueError as exc:
        # Conflit d'insertion concurrente (race condition sync) → 409, le client retry
        raise HTTPException(status_code=409, detail=str(exc))

    log_audit(
        db, user_id=current_user.id, action="SYNC_ATTENDANCES",
        resource_type="ATTENDANCE",
        ip_address=get_client_ip(request),
        user_agent=request.headers.get("user-agent"),
        details={"device_id": data.device_id, "scans_count": len(data.scans),
                 "inserted": result.total_inserted, "duplicates": len(result.duplicate)},
    )

    return result


# ----------------------------------------------------------------
# Endpoints de consultation (direction/admin)
# ----------------------------------------------------------------

@router.get(
    "/logs",
    response_model=SyncLogPage,
    summary="Lister les journaux de synchronisation",
)
def get_sync_logs(
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
    status: Optional[str] = Query(None),
    trip_id: Optional[str] = Query(None),
    current_user: User = Depends(_admin),
    db: Session = Depends(get_db),
):
    """Retourne les sync_logs paginés, du plus récent au plus ancien, scopés par école."""
    query = select(SyncLog).join(Trip, Trip.id == SyncLog.trip_id).where(Trip.school_id == current_user.school_id)

    if status:
        query = query.where(SyncLog.status == status)
    if trip_id:
        query = query.where(SyncLog.trip_id == trip_id)

    # Total
    count_q = select(func.count()).select_from(query.subquery())
    total = db.execute(count_q).scalar() or 0
    total_pages = max(1, math.ceil(total / page_size))

    # Fetch page
    rows = db.execute(
        query.order_by(SyncLog.synced_at.desc())
        .offset((page - 1) * page_size)
        .limit(page_size)
    ).scalars().all()

    # Enrichir avec user_email et trip_name
    user_ids = {r.user_id for r in rows if r.user_id}
    trip_ids = {r.trip_id for r in rows if r.trip_id}

    user_map = {}
    if user_ids:
        users = db.execute(
            select(User.id, User.email).where(User.id.in_(user_ids))
        ).all()
        user_map = {u.id: u.email for u in users}

    trip_map = {}
    if trip_ids:
        trips = db.execute(
            select(Trip.id, Trip.destination).where(Trip.id.in_(trip_ids))
        ).all()
        trip_map = {t.id: t.destination for t in trips}

    items = []
    for row in rows:
        items.append(SyncLogOut(
            id=row.id,
            user_id=str(row.user_id) if row.user_id else None,
            user_email=user_map.get(row.user_id),
            trip_id=str(row.trip_id) if row.trip_id else None,
            trip_name=trip_map.get(row.trip_id),
            device_id=row.device_id,
            records_synced=row.records_synced or 0,
            conflicts_detected=row.conflicts_detected or 0,
            status=row.status,
            error_details=row.error_details,
            synced_at=row.synced_at,
        ))

    return SyncLogPage(
        items=items,
        total=total,
        page=page,
        page_size=page_size,
        total_pages=total_pages,
    )


@router.get(
    "/stats",
    response_model=SyncStats,
    summary="Statistiques globales de synchronisation",
)
def get_sync_stats(
    current_user: User = Depends(_admin),
    db: Session = Depends(get_db),
):
    """Retourne les compteurs globaux des synchronisations, scopés par école."""
    school_filter = select(SyncLog.id).join(Trip, Trip.id == SyncLog.trip_id).where(Trip.school_id == current_user.school_id)
    base = select(SyncLog).join(Trip, Trip.id == SyncLog.trip_id).where(Trip.school_id == current_user.school_id)

    total = db.execute(select(func.count()).select_from(base.subquery())).scalar() or 0
    total_synced = db.execute(select(func.coalesce(func.sum(SyncLog.records_synced), 0)).join(Trip, Trip.id == SyncLog.trip_id).where(Trip.school_id == current_user.school_id)).scalar()
    total_conflicts = db.execute(select(func.coalesce(func.sum(SyncLog.conflicts_detected), 0)).join(Trip, Trip.id == SyncLog.trip_id).where(Trip.school_id == current_user.school_id)).scalar()

    success = db.execute(
        select(func.count(SyncLog.id)).join(Trip, Trip.id == SyncLog.trip_id).where(Trip.school_id == current_user.school_id, SyncLog.status == "SUCCESS")
    ).scalar() or 0
    partial = db.execute(
        select(func.count(SyncLog.id)).join(Trip, Trip.id == SyncLog.trip_id).where(Trip.school_id == current_user.school_id, SyncLog.status == "PARTIAL")
    ).scalar() or 0
    failed = db.execute(
        select(func.count(SyncLog.id)).join(Trip, Trip.id == SyncLog.trip_id).where(Trip.school_id == current_user.school_id, SyncLog.status == "FAILED")
    ).scalar() or 0

    last_sync = db.execute(
        select(func.max(SyncLog.synced_at)).join(Trip, Trip.id == SyncLog.trip_id).where(Trip.school_id == current_user.school_id)
    ).scalar()

    return SyncStats(
        total_syncs=total,
        total_records_synced=total_synced,
        total_conflicts=total_conflicts,
        success_count=success,
        partial_count=partial,
        failed_count=failed,
        last_sync_at=last_sync,
    )
