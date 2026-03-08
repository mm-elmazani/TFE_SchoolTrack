"""
Tests du router audit (US 6.4).
Verification des filtres, pagination et permissions.
"""

import uuid
from datetime import datetime
from unittest.mock import MagicMock, patch

import pytest
from fastapi.testclient import TestClient

from app.database import get_db
from app.dependencies import get_current_user
from app.main import app
from app.models.user import User


# ── Helpers ──────────────────────────────────────────────────────────────

def _make_user(role: str = "DIRECTION") -> User:
    user = User()
    user.id = uuid.uuid4()
    user.email = f"{role.lower()}@schooltrack.be"
    user.password_hash = "$2b$12$fake"
    user.first_name = "Test"
    user.last_name = role.title()
    user.role = role
    user.totp_secret = None
    user.is_2fa_enabled = False
    user.failed_attempts = 0
    user.locked_until = None
    user.last_login = None
    return user


def _mock_audit_rows(count: int = 3):
    """Genere des lignes simulees pour les requetes audit_logs."""
    rows = []
    for i in range(count):
        rows.append((
            i + 1,                                  # id
            uuid.uuid4(),                           # user_id
            f"user{i}@schooltrack.be",              # user_email
            "LOGIN_SUCCESS",                        # action
            "AUTH",                                  # resource_type
            None,                                   # resource_id
            "127.0.0.1",                            # ip_address
            "TestAgent/1.0",                        # user_agent
            {"email": f"user{i}@schooltrack.be"},   # details
            datetime(2026, 3, 8, 10, 0, i),         # performed_at
        ))
    return rows


# ── Fixtures ─────────────────────────────────────────────────────────────

@pytest.fixture
def direction_client():
    mock_db = MagicMock()
    # Par defaut : count = 3, rows = 3
    mock_db.execute.return_value.scalar.return_value = 3
    mock_db.execute.return_value.fetchall.return_value = _mock_audit_rows(3)
    app.dependency_overrides[get_db] = lambda: mock_db
    app.dependency_overrides[get_current_user] = lambda: _make_user("DIRECTION")
    with TestClient(app) as c:
        yield c, mock_db
    app.dependency_overrides.clear()


@pytest.fixture
def admin_tech_client():
    mock_db = MagicMock()
    mock_db.execute.return_value.scalar.return_value = 1
    mock_db.execute.return_value.fetchall.return_value = _mock_audit_rows(1)
    app.dependency_overrides[get_db] = lambda: mock_db
    app.dependency_overrides[get_current_user] = lambda: _make_user("ADMIN_TECH")
    with TestClient(app) as c:
        yield c, mock_db
    app.dependency_overrides.clear()


@pytest.fixture
def teacher_client():
    mock_db = MagicMock()
    app.dependency_overrides[get_db] = lambda: mock_db
    app.dependency_overrides[get_current_user] = lambda: _make_user("TEACHER")
    with TestClient(app) as c:
        yield c, mock_db
    app.dependency_overrides.clear()


@pytest.fixture
def observer_client():
    mock_db = MagicMock()
    app.dependency_overrides[get_db] = lambda: mock_db
    app.dependency_overrides[get_current_user] = lambda: _make_user("OBSERVER")
    with TestClient(app) as c:
        yield c, mock_db
    app.dependency_overrides.clear()


@pytest.fixture
def no_auth_client():
    mock_db = MagicMock()
    app.dependency_overrides[get_db] = lambda: mock_db
    app.dependency_overrides.pop(get_current_user, None)
    with TestClient(app) as c:
        yield c
    app.dependency_overrides.clear()


# ── Tests permissions ────────────────────────────────────────────────────

class TestAuditPermissions:
    """Seuls DIRECTION et ADMIN_TECH peuvent consulter les logs."""

    def test_direction_can_access(self, direction_client):
        client, _ = direction_client
        resp = client.get("/api/v1/audit/logs")
        assert resp.status_code == 200

    def test_admin_tech_can_access(self, admin_tech_client):
        client, _ = admin_tech_client
        resp = client.get("/api/v1/audit/logs")
        assert resp.status_code == 200

    def test_teacher_forbidden(self, teacher_client):
        client, _ = teacher_client
        resp = client.get("/api/v1/audit/logs")
        assert resp.status_code == 403

    def test_observer_forbidden(self, observer_client):
        client, _ = observer_client
        resp = client.get("/api/v1/audit/logs")
        assert resp.status_code == 403

    def test_no_auth_forbidden(self, no_auth_client):
        resp = no_auth_client.get("/api/v1/audit/logs")
        assert resp.status_code == 403


# ── Tests reponse et pagination ──────────────────────────────────────────

class TestAuditResponse:
    """Verification de la structure de reponse et de la pagination."""

    def test_default_pagination(self, direction_client):
        client, _ = direction_client
        resp = client.get("/api/v1/audit/logs")
        data = resp.json()
        assert data["page"] == 1
        assert data["page_size"] == 50
        assert data["total"] == 3
        assert data["total_pages"] == 1
        assert len(data["items"]) == 3

    def test_custom_page_size(self, direction_client):
        client, mock_db = direction_client
        # Simuler 10 items, page_size=2
        mock_db.execute.return_value.scalar.return_value = 10
        mock_db.execute.return_value.fetchall.return_value = _mock_audit_rows(2)
        resp = client.get("/api/v1/audit/logs?page=1&page_size=2")
        data = resp.json()
        assert data["page"] == 1
        assert data["page_size"] == 2
        assert data["total"] == 10
        assert data["total_pages"] == 5
        assert len(data["items"]) == 2

    def test_item_structure(self, direction_client):
        client, _ = direction_client
        resp = client.get("/api/v1/audit/logs")
        item = resp.json()["items"][0]
        assert "id" in item
        assert "user_id" in item
        assert "user_email" in item
        assert "action" in item
        assert "resource_type" in item
        assert "ip_address" in item
        assert "user_agent" in item
        assert "details" in item
        assert "performed_at" in item

    def test_page_size_max_200(self, direction_client):
        client, _ = direction_client
        resp = client.get("/api/v1/audit/logs?page_size=300")
        assert resp.status_code == 422  # Validation error

    def test_page_min_1(self, direction_client):
        client, _ = direction_client
        resp = client.get("/api/v1/audit/logs?page=0")
        assert resp.status_code == 422


# ── Tests filtres ────────────────────────────────────────────────────────

class TestAuditFilters:
    """Verification que les filtres sont passes dans la requete SQL."""

    def test_filter_by_action(self, direction_client):
        client, mock_db = direction_client
        resp = client.get("/api/v1/audit/logs?action=LOGIN_SUCCESS")
        assert resp.status_code == 200
        # Verifie que la requete contient le filtre action
        calls = mock_db.execute.call_args_list
        # Le deuxieme appel est la requete de donnees
        sql_params = calls[1][0][1] if len(calls) > 1 else calls[0][0][1]
        assert sql_params.get("action") == "LOGIN_SUCCESS"

    def test_filter_by_resource_type(self, direction_client):
        client, mock_db = direction_client
        resp = client.get("/api/v1/audit/logs?resource_type=STUDENT")
        assert resp.status_code == 200
        calls = mock_db.execute.call_args_list
        sql_params = calls[1][0][1] if len(calls) > 1 else calls[0][0][1]
        assert sql_params.get("resource_type") == "STUDENT"

    def test_filter_by_user_id(self, direction_client):
        client, mock_db = direction_client
        uid = str(uuid.uuid4())
        resp = client.get(f"/api/v1/audit/logs?user_id={uid}")
        assert resp.status_code == 200
        calls = mock_db.execute.call_args_list
        sql_params = calls[1][0][1] if len(calls) > 1 else calls[0][0][1]
        assert sql_params.get("user_id") == uid

    def test_filter_by_date_range(self, direction_client):
        client, mock_db = direction_client
        resp = client.get("/api/v1/audit/logs?date_from=2026-03-01&date_to=2026-03-08")
        assert resp.status_code == 200
        calls = mock_db.execute.call_args_list
        sql_params = calls[1][0][1] if len(calls) > 1 else calls[0][0][1]
        assert "date_from" in sql_params
        assert "date_to" in sql_params

    def test_no_filters(self, direction_client):
        client, _ = direction_client
        resp = client.get("/api/v1/audit/logs")
        assert resp.status_code == 200

    def test_empty_results(self, direction_client):
        client, mock_db = direction_client
        mock_db.execute.return_value.scalar.return_value = 0
        mock_db.execute.return_value.fetchall.return_value = []
        resp = client.get("/api/v1/audit/logs?action=NONEXISTENT")
        data = resp.json()
        assert data["total"] == 0
        assert data["items"] == []
        assert data["total_pages"] == 1


# ── Tests export JSON ───────────────────────────────────────────────────

class TestAuditExport:
    """Verification de l'export JSON pour audit externe."""

    def test_export_returns_json_file(self, direction_client):
        client, _ = direction_client
        resp = client.get("/api/v1/audit/logs/export")
        assert resp.status_code == 200
        assert "application/json" in resp.headers["content-type"]
        assert "attachment" in resp.headers["content-disposition"]
        assert "audit_logs_" in resp.headers["content-disposition"]

    def test_export_structure(self, direction_client):
        client, _ = direction_client
        resp = client.get("/api/v1/audit/logs/export")
        data = resp.json()
        assert "exported_at" in data
        assert "exported_by" in data
        assert "total" in data
        assert "filters" in data
        assert "logs" in data
        assert data["total"] == 3
        assert len(data["logs"]) == 3

    def test_export_with_filters(self, direction_client):
        client, mock_db = direction_client
        mock_db.execute.return_value.fetchall.return_value = _mock_audit_rows(1)
        resp = client.get("/api/v1/audit/logs/export?action=LOGIN_SUCCESS&date_from=2026-03-01")
        data = resp.json()
        assert data["filters"]["action"] == "LOGIN_SUCCESS"
        assert data["filters"]["date_from"] == "2026-03-01"

    def test_export_empty(self, direction_client):
        client, mock_db = direction_client
        mock_db.execute.return_value.fetchall.return_value = []
        resp = client.get("/api/v1/audit/logs/export")
        data = resp.json()
        assert data["total"] == 0
        assert data["logs"] == []

    def test_export_log_item_fields(self, direction_client):
        client, _ = direction_client
        resp = client.get("/api/v1/audit/logs/export")
        log_item = resp.json()["logs"][0]
        assert "id" in log_item
        assert "user_id" in log_item
        assert "user_email" in log_item
        assert "action" in log_item
        assert "performed_at" in log_item

    def test_export_forbidden_teacher(self, teacher_client):
        client, _ = teacher_client
        resp = client.get("/api/v1/audit/logs/export")
        assert resp.status_code == 403

    def test_export_forbidden_observer(self, observer_client):
        client, _ = observer_client
        resp = client.get("/api/v1/audit/logs/export")
        assert resp.status_code == 403

    def test_export_admin_tech_allowed(self, admin_tech_client):
        client, _ = admin_tech_client
        resp = client.get("/api/v1/audit/logs/export")
        assert resp.status_code == 200
