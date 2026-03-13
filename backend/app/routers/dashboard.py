"""
Router pour le dashboard de supervision (US 4.2).
Lecture : DIRECTION et ADMIN_TECH.
"""

from typing import Optional

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.database import get_db
from app.dependencies import require_role
from app.models.user import User
from app.schemas.dashboard import DashboardOverview
from app.services import dashboard_service

router = APIRouter(prefix="/api/v1/dashboard", tags=["Dashboard"])

_admin = require_role("DIRECTION", "ADMIN_TECH")


@router.get("/overview", response_model=DashboardOverview, summary="Vue d'ensemble (US 4.2)")
def get_overview(
    status: Optional[str] = Query(None, description="Filtre statut (ACTIVE, PLANNED, COMPLETED, ALL)"),
    current_user: User = Depends(_admin),
    db: Session = Depends(get_db),
):
    """
    Retourne les statistiques aggregees pour le dashboard direction :
    voyages, presences, checkpoints, modes de scan.
    Auto-refresh cote client (pas de log audit pour eviter le spam).
    """
    return dashboard_service.get_dashboard_overview(db, status_filter=status)
