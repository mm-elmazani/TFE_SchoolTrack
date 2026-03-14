"""
Tests d'integration API pour le dashboard de supervision (US 4.2).
"""

import uuid
from datetime import date, datetime
from unittest.mock import MagicMock, patch

from app.schemas.dashboard import (
    DashboardOverview,
    DashboardTripSummary,
    ScanMethodStats,
)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _make_overview(**kwargs) -> DashboardOverview:
    return DashboardOverview(
        total_trips=kwargs.get("total_trips", 2),
        active_trips=kwargs.get("active_trips", 1),
        planned_trips=kwargs.get("planned_trips", 1),
        completed_trips=kwargs.get("completed_trips", 0),
        total_students=kwargs.get("total_students", 30),
        total_attendances=kwargs.get("total_attendances", 50),
        global_attendance_rate=kwargs.get("global_attendance_rate", 75.0),
        scan_method_stats=kwargs.get("scan_method_stats", ScanMethodStats(nfc=30, qr_physical=10, qr_digital=5, manual=5, total=50)),
        trips=kwargs.get("trips", []),
        generated_at=datetime.now(),
    )


# ============================================================
# Tests API
# ============================================================


def test_overview_200(client):
    """GET /api/v1/dashboard/overview → 200 avec structure correcte."""
    with patch("app.routers.dashboard.dashboard_service.get_dashboard_overview") as mock:
        mock.return_value = _make_overview()

        response = client.get("/api/v1/dashboard/overview")

    assert response.status_code == 200
    data = response.json()
    assert data["total_trips"] == 2
    assert data["active_trips"] == 1
    assert data["global_attendance_rate"] == 75.0
    assert "scan_method_stats" in data
    assert data["scan_method_stats"]["nfc"] == 30


def test_overview_empty(client):
    """Dashboard vide → 200 avec zeros."""
    with patch("app.routers.dashboard.dashboard_service.get_dashboard_overview") as mock:
        mock.return_value = _make_overview(
            total_trips=0, active_trips=0, planned_trips=0, completed_trips=0,
            total_students=0, total_attendances=0, global_attendance_rate=0.0,
            scan_method_stats=ScanMethodStats(), trips=[],
        )

        response = client.get("/api/v1/dashboard/overview")

    assert response.status_code == 200
    assert response.json()["total_trips"] == 0


def test_overview_with_status_filter(client):
    """Filtre statut passe au service."""
    with patch("app.routers.dashboard.dashboard_service.get_dashboard_overview") as mock:
        mock.return_value = _make_overview(total_trips=1, active_trips=1)

        response = client.get("/api/v1/dashboard/overview?status=ACTIVE")

    assert response.status_code == 200
    mock.assert_called_once()
    # Verifier que le filtre est passe
    call_kwargs = mock.call_args
    assert call_kwargs[1].get("status_filter") == "ACTIVE" or call_kwargs[0][1] == "ACTIVE"


def test_overview_with_trips_data(client):
    """Dashboard avec des voyages detailles."""
    trip_summary = DashboardTripSummary(
        id=uuid.uuid4(),
        destination="Bruges",
        date=date(2026, 3, 15),
        status="ACTIVE",
        total_students=20,
        total_present=15,
        attendance_rate=75.0,
        total_checkpoints=3,
        closed_checkpoints=2,
        last_checkpoint=None,
        checkpoints=[],
    )

    with patch("app.routers.dashboard.dashboard_service.get_dashboard_overview") as mock:
        mock.return_value = _make_overview(trips=[trip_summary])

        response = client.get("/api/v1/dashboard/overview")

    assert response.status_code == 200
    trips = response.json()["trips"]
    assert len(trips) == 1
    assert trips[0]["destination"] == "Bruges"
    assert trips[0]["attendance_rate"] == 75.0


def test_overview_403_teacher(client):
    """Role TEACHER → 403."""
    from app.dependencies import get_current_user
    from app.main import app
    from app.models.user import User

    teacher = MagicMock(spec=User)
    teacher.id = uuid.uuid4()
    teacher.role = "TEACHER"
    teacher.email = "t@schooltrack.be"
    teacher.is_2fa_enabled = False
    teacher.totp_secret = None

    app.dependency_overrides[get_current_user] = lambda: teacher

    response = client.get("/api/v1/dashboard/overview")

    assert response.status_code == 403


def test_overview_generated_at_present(client):
    """Le champ generated_at est present dans la reponse."""
    with patch("app.routers.dashboard.dashboard_service.get_dashboard_overview") as mock:
        mock.return_value = _make_overview()

        response = client.get("/api/v1/dashboard/overview")

    assert response.status_code == 200
    assert "generated_at" in response.json()
