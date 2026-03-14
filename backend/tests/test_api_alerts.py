"""
Tests d'integration API pour les alertes temps reel (US 4.3).
"""

import uuid
from datetime import datetime
from unittest.mock import MagicMock, patch

from app.schemas.alert import AlertResponse, AlertStats


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _make_alert_response(**kwargs) -> AlertResponse:
    return AlertResponse(
        id=kwargs.get("id", uuid.uuid4()),
        trip_id=kwargs.get("trip_id", uuid.uuid4()),
        student_id=kwargs.get("student_id", uuid.uuid4()),
        student_name=kwargs.get("student_name", "Dupont Marie"),
        trip_destination=kwargs.get("trip_destination", "Bruges"),
        alert_type=kwargs.get("alert_type", "STUDENT_MISSING"),
        severity=kwargs.get("severity", "HIGH"),
        message=kwargs.get("message", "Eleve absent"),
        status=kwargs.get("status", "ACTIVE"),
        created_at=datetime.now(),
    )


# ============================================================
# POST /api/v1/alerts
# ============================================================

def test_create_alert_201(client):
    """Creation d'une alerte → 201."""
    trip_id = uuid.uuid4()
    student_id = uuid.uuid4()

    with patch("app.routers.alerts.alert_service.create_alert") as mock:
        mock.return_value = _make_alert_response(
            trip_id=trip_id, student_id=student_id
        )

        response = client.post("/api/v1/alerts", json={
            "trip_id": str(trip_id),
            "student_id": str(student_id),
            "alert_type": "STUDENT_MISSING",
            "severity": "HIGH",
        })

    assert response.status_code == 201
    assert response.json()["alert_type"] == "STUDENT_MISSING"


def test_create_alert_404_trip(client):
    """Voyage introuvable → 404."""
    with patch("app.routers.alerts.alert_service.create_alert") as mock:
        mock.side_effect = ValueError("Voyage introuvable.")

        response = client.post("/api/v1/alerts", json={
            "trip_id": str(uuid.uuid4()),
            "student_id": str(uuid.uuid4()),
            "alert_type": "STUDENT_MISSING",
        })

    assert response.status_code == 404


# ============================================================
# GET /api/v1/alerts
# ============================================================

def test_list_alerts_200(client):
    """Liste des alertes → 200."""
    with patch("app.routers.alerts.alert_service.get_alerts") as mock:
        mock.return_value = [_make_alert_response(), _make_alert_response()]

        response = client.get("/api/v1/alerts")

    assert response.status_code == 200
    assert len(response.json()) == 2


def test_list_alerts_with_filter(client):
    """Filtre par statut → passe au service."""
    with patch("app.routers.alerts.alert_service.get_alerts") as mock:
        mock.return_value = [_make_alert_response()]

        response = client.get("/api/v1/alerts?status=ACTIVE")

    assert response.status_code == 200
    mock.assert_called_once()


# ============================================================
# GET /api/v1/alerts/active
# ============================================================

def test_active_alerts_200(client):
    """Alertes actives → 200."""
    with patch("app.routers.alerts.alert_service.get_active_alerts") as mock:
        mock.return_value = [_make_alert_response()]

        response = client.get("/api/v1/alerts/active")

    assert response.status_code == 200


# ============================================================
# GET /api/v1/alerts/stats
# ============================================================

def test_alert_stats_200(client):
    """Stats alertes → 200."""
    with patch("app.routers.alerts.alert_service.get_alert_stats") as mock:
        mock.return_value = AlertStats(total=5, active=2, in_progress=1, resolved=2, critical=1)

        response = client.get("/api/v1/alerts/stats")

    assert response.status_code == 200
    data = response.json()
    assert data["total"] == 5
    assert data["active"] == 2
    assert data["critical"] == 1


# ============================================================
# PATCH /api/v1/alerts/{id}
# ============================================================

def test_resolve_alert_200(client):
    """Resolution d'une alerte → 200."""
    alert_id = uuid.uuid4()

    with patch("app.routers.alerts.alert_service.update_alert_status") as mock:
        mock.return_value = _make_alert_response(id=alert_id, status="RESOLVED")

        response = client.patch(
            f"/api/v1/alerts/{alert_id}",
            json={"status": "RESOLVED"},
        )

    assert response.status_code == 200
    assert response.json()["status"] == "RESOLVED"


def test_resolve_alert_404(client):
    """Alerte introuvable → 404."""
    with patch("app.routers.alerts.alert_service.update_alert_status") as mock:
        mock.side_effect = ValueError("Alerte introuvable.")

        response = client.patch(
            f"/api/v1/alerts/{uuid.uuid4()}",
            json={"status": "RESOLVED"},
        )

    assert response.status_code == 404


def test_alerts_403_teacher(client):
    """TEACHER ne peut pas lire les alertes (seulement creer)."""
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

    response = client.get("/api/v1/alerts")
    assert response.status_code == 403


def test_teacher_can_create_alert(client):
    """TEACHER peut creer une alerte (signaler eleve manquant)."""
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

    with patch("app.routers.alerts.alert_service.create_alert") as mock:
        mock.return_value = _make_alert_response()

        response = client.post("/api/v1/alerts", json={
            "trip_id": str(uuid.uuid4()),
            "student_id": str(uuid.uuid4()),
            "alert_type": "STUDENT_MISSING",
        })

    assert response.status_code == 201
