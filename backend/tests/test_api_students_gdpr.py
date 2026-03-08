"""
Tests pour l'export RGPD des donnees personnelles d'un eleve (US 6.5).
GET /api/v1/students/{id}/data-export
"""

import uuid
from datetime import datetime
from unittest.mock import MagicMock, patch, call

import pytest
from fastapi.testclient import TestClient

from app.database import get_db
from app.dependencies import get_current_user
from app.main import app
from app.models.student import Student
from app.models.user import User


# --- Helpers ---

def _make_user(role="DIRECTION"):
    user = User()
    user.id = uuid.uuid4()
    user.email = "admin@schooltrack.be"
    user.password_hash = "$2b$12$fake"
    user.first_name = "Test"
    user.last_name = "Admin"
    user.role = role
    user.totp_secret = None
    user.is_2fa_enabled = False
    user.failed_attempts = 0
    user.locked_until = None
    user.last_login = None
    return user


def _make_student(**kwargs):
    s = MagicMock(spec=Student)
    s.id = kwargs.get("id", uuid.uuid4())
    s.first_name = kwargs.get("first_name", "Jean")
    s.last_name = kwargs.get("last_name", "Dupont")
    s.email = kwargs.get("email", "jean@school.be")
    s.photo_url = kwargs.get("photo_url", None)
    s.parent_consent = kwargs.get("parent_consent", False)
    s.is_deleted = kwargs.get("is_deleted", False)
    s.created_at = kwargs.get("created_at", datetime(2025, 1, 15, 10, 0))
    s.updated_at = kwargs.get("updated_at", datetime(2025, 1, 15, 10, 0))
    s.deleted_at = kwargs.get("deleted_at", None)
    s.deleted_by = kwargs.get("deleted_by", None)
    return s


# ============================================================
# Permissions
# ============================================================

class TestGdprExportPermissions:

    def test_direction_allowed(self):
        sid = uuid.uuid4()
        student = _make_student(id=sid)
        mock_db = MagicMock()
        mock_db.get.return_value = student
        mock_db.execute.return_value.fetchall.return_value = []

        app.dependency_overrides[get_db] = lambda: mock_db
        app.dependency_overrides[get_current_user] = lambda: _make_user("DIRECTION")

        with TestClient(app) as c:
            r = c.get(f"/api/v1/students/{sid}/data-export")
        app.dependency_overrides.clear()

        assert r.status_code == 200

    def test_admin_tech_allowed(self):
        sid = uuid.uuid4()
        student = _make_student(id=sid)
        mock_db = MagicMock()
        mock_db.get.return_value = student
        mock_db.execute.return_value.fetchall.return_value = []

        app.dependency_overrides[get_db] = lambda: mock_db
        app.dependency_overrides[get_current_user] = lambda: _make_user("ADMIN_TECH")

        with TestClient(app) as c:
            r = c.get(f"/api/v1/students/{sid}/data-export")
        app.dependency_overrides.clear()

        assert r.status_code == 200

    def test_teacher_forbidden(self):
        sid = uuid.uuid4()
        app.dependency_overrides[get_current_user] = lambda: _make_user("TEACHER")

        with TestClient(app) as c:
            r = c.get(f"/api/v1/students/{sid}/data-export")
        app.dependency_overrides.clear()

        assert r.status_code == 403

    def test_observer_forbidden(self):
        sid = uuid.uuid4()
        app.dependency_overrides[get_current_user] = lambda: _make_user("OBSERVER")

        with TestClient(app) as c:
            r = c.get(f"/api/v1/students/{sid}/data-export")
        app.dependency_overrides.clear()

        assert r.status_code == 403


# ============================================================
# Reponses
# ============================================================

class TestGdprExportResponse:

    def _setup(self, student_id=None):
        sid = student_id or uuid.uuid4()
        student = _make_student(id=sid, first_name="Alice", last_name="Martin",
                                email="alice@school.be", parent_consent=True)
        mock_db = MagicMock()
        mock_db.get.return_value = student
        mock_db.execute.return_value.fetchall.return_value = []

        app.dependency_overrides[get_db] = lambda: mock_db
        app.dependency_overrides[get_current_user] = lambda: _make_user("DIRECTION")
        return sid, mock_db

    def test_export_returns_200(self):
        sid, _ = self._setup()
        with TestClient(app) as c:
            r = c.get(f"/api/v1/students/{sid}/data-export")
        app.dependency_overrides.clear()
        assert r.status_code == 200

    def test_export_contains_student_data(self):
        sid, _ = self._setup()
        with TestClient(app) as c:
            data = c.get(f"/api/v1/students/{sid}/data-export").json()
        app.dependency_overrides.clear()

        assert data["student"]["first_name"] == "Alice"
        assert data["student"]["last_name"] == "Martin"
        assert data["student"]["email"] == "alice@school.be"
        assert data["student"]["parent_consent"] is True
        assert data["student"]["id"] == str(sid)

    def test_export_structure(self):
        sid, _ = self._setup()
        with TestClient(app) as c:
            data = c.get(f"/api/v1/students/{sid}/data-export").json()
        app.dependency_overrides.clear()

        assert "exported_at" in data
        assert "student" in data
        assert "classes" in data
        assert "trips" in data
        assert "attendances" in data
        assert "assignments" in data
        assert "alerts" in data

    def test_export_empty_relations(self):
        sid, _ = self._setup()
        with TestClient(app) as c:
            data = c.get(f"/api/v1/students/{sid}/data-export").json()
        app.dependency_overrides.clear()

        assert data["classes"] == []
        assert data["trips"] == []
        assert data["attendances"] == []
        assert data["assignments"] == []
        assert data["alerts"] == []

    def test_export_student_not_found(self):
        sid = uuid.uuid4()
        mock_db = MagicMock()
        mock_db.get.return_value = None

        app.dependency_overrides[get_db] = lambda: mock_db
        app.dependency_overrides[get_current_user] = lambda: _make_user("DIRECTION")

        with TestClient(app) as c:
            r = c.get(f"/api/v1/students/{sid}/data-export")
        app.dependency_overrides.clear()

        assert r.status_code == 404

    def test_export_deleted_student_allowed(self):
        """L'export RGPD est autorise meme pour un eleve supprime (droit d'acces)."""
        sid = uuid.uuid4()
        student = _make_student(id=sid, is_deleted=True,
                                deleted_at=datetime(2025, 6, 1))
        mock_db = MagicMock()
        mock_db.get.return_value = student
        mock_db.execute.return_value.fetchall.return_value = []

        app.dependency_overrides[get_db] = lambda: mock_db
        app.dependency_overrides[get_current_user] = lambda: _make_user("DIRECTION")

        with TestClient(app) as c:
            r = c.get(f"/api/v1/students/{sid}/data-export")
        app.dependency_overrides.clear()

        assert r.status_code == 200
        data = r.json()
        assert data["student"]["is_deleted"] is True

    def test_export_uuid_invalide(self):
        app.dependency_overrides[get_current_user] = lambda: _make_user("DIRECTION")
        with TestClient(app) as c:
            r = c.get("/api/v1/students/pas-un-uuid/data-export")
        app.dependency_overrides.clear()
        assert r.status_code == 422
