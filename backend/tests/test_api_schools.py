"""
Tests d'integration API pour les ecoles (US 6.6 — multi-tenancy).
Testent les endpoints publics et proteges du router schools.
"""

import uuid
from datetime import datetime
from unittest.mock import MagicMock, patch

import pytest
from fastapi.testclient import TestClient

from app.database import get_db
from app.dependencies import get_current_user
from app.main import app
from app.models.school import School
from app.models.user import User


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

_SCHOOL_ID = uuid.uuid4()


def _make_school(**kwargs):
    """Cree un objet School factice pour les mocks."""
    school = MagicMock(spec=School)
    school.id = kwargs.get("id", _SCHOOL_ID)
    school.name = kwargs.get("name", "Ecole de test")
    school.slug = kwargs.get("slug", "test")
    school.is_active = kwargs.get("is_active", True)
    school.created_at = kwargs.get("created_at", datetime.now())
    return school


def _make_user(role="DIRECTION"):
    """Cree un utilisateur fictif avec le role donne."""
    user = User()
    user.id = uuid.uuid4()
    user.school_id = _SCHOOL_ID
    user.email = "test@schooltrack.be"
    user.password_hash = "$2b$12$fake"
    user.first_name = "Test"
    user.last_name = "User"
    user.role = role
    user.totp_secret = None
    user.is_2fa_enabled = False
    user.failed_attempts = 0
    user.locked_until = None
    user.last_login = None
    return user


@pytest.fixture
def mock_db():
    return MagicMock()


@pytest.fixture
def public_client(mock_db):
    """Client HTTP sans authentification (endpoints publics)."""
    app.dependency_overrides[get_db] = lambda: mock_db
    # Pas d'override de get_current_user — les endpoints publics n'en ont pas besoin
    with TestClient(app) as c:
        yield c
    app.dependency_overrides.clear()


@pytest.fixture
def direction_client(mock_db):
    """Client HTTP avec un utilisateur DIRECTION."""
    app.dependency_overrides[get_db] = lambda: mock_db
    app.dependency_overrides[get_current_user] = lambda: _make_user("DIRECTION")
    with TestClient(app) as c:
        yield c
    app.dependency_overrides.clear()


@pytest.fixture
def admin_client(mock_db):
    """Client HTTP avec un utilisateur ADMIN_TECH."""
    app.dependency_overrides[get_db] = lambda: mock_db
    app.dependency_overrides[get_current_user] = lambda: _make_user("ADMIN_TECH")
    with TestClient(app) as c:
        yield c
    app.dependency_overrides.clear()


@pytest.fixture
def teacher_client(mock_db):
    """Client HTTP avec un utilisateur TEACHER (role non autorise)."""
    app.dependency_overrides[get_db] = lambda: mock_db
    app.dependency_overrides[get_current_user] = lambda: _make_user("TEACHER")
    with TestClient(app) as c:
        yield c
    app.dependency_overrides.clear()


# ============================================================
# GET /api/v1/schools/public
# ============================================================

class TestListSchoolsPublic:
    """Tests de l'endpoint public de liste des ecoles."""

    def test_returns_active_schools(self, public_client, mock_db):
        """Retourne les ecoles actives avec name + slug."""
        mock_row_1 = MagicMock()
        mock_row_1.name = "CEPES"
        mock_row_1.slug = "cepes"
        mock_row_2 = MagicMock()
        mock_row_2.name = "Ecole dev"
        mock_row_2.slug = "dev"
        mock_db.execute.return_value.all.return_value = [mock_row_1, mock_row_2]

        response = public_client.get("/api/v1/schools/public")

        assert response.status_code == 200
        data = response.json()
        assert len(data) == 2
        assert data[0]["name"] == "CEPES"
        assert data[0]["slug"] == "cepes"

    def test_returns_empty_list(self, public_client, mock_db):
        """Retourne une liste vide si aucune ecole active."""
        mock_db.execute.return_value.all.return_value = []

        response = public_client.get("/api/v1/schools/public")

        assert response.status_code == 200
        assert response.json() == []


# ============================================================
# GET /api/v1/schools/{slug}/exists
# ============================================================

class TestSchoolExists:
    """Tests de l'endpoint de verification d'existence d'une ecole."""

    def test_found_200(self, public_client, mock_db):
        """Ecole existante et active → 200 avec slug + name."""
        school = _make_school(slug="cepes", name="CEPES")
        mock_db.execute.return_value.scalar_one_or_none.return_value = school

        response = public_client.get("/api/v1/schools/cepes/exists")

        assert response.status_code == 200
        assert response.json()["slug"] == "cepes"
        assert response.json()["name"] == "CEPES"

    def test_not_found_404(self, public_client, mock_db):
        """Ecole inexistante → 404."""
        mock_db.execute.return_value.scalar_one_or_none.return_value = None

        response = public_client.get("/api/v1/schools/unknown/exists")

        assert response.status_code == 404
        assert "introuvable" in response.json()["detail"]


# ============================================================
# GET /api/v1/schools
# ============================================================

class TestListSchools:
    """Tests de l'endpoint protege de liste des ecoles."""

    def test_direction_can_list(self, direction_client, mock_db):
        """DIRECTION peut lister les ecoles → 200."""
        school = _make_school()
        mock_db.execute.return_value.scalars.return_value.all.return_value = [school]

        response = direction_client.get("/api/v1/schools")

        assert response.status_code == 200
        assert len(response.json()) == 1

    def test_admin_can_list(self, admin_client, mock_db):
        """ADMIN_TECH peut aussi lister les ecoles → 200."""
        mock_db.execute.return_value.scalars.return_value.all.return_value = []

        response = admin_client.get("/api/v1/schools")

        assert response.status_code == 200

    def test_teacher_forbidden(self, teacher_client):
        """TEACHER ne peut pas lister les ecoles → 403."""
        response = teacher_client.get("/api/v1/schools")

        assert response.status_code == 403


# ============================================================
# POST /api/v1/schools
# ============================================================

class TestCreateSchool:
    """Tests de creation d'ecole (ADMIN_TECH uniquement)."""

    def test_admin_can_create(self, admin_client, mock_db):
        """ADMIN_TECH peut creer une ecole → 201."""
        # db.refresh doit peupler l'objet School avec id + created_at
        def _fake_refresh(obj):
            obj.id = _SCHOOL_ID
            obj.name = obj.name or "Nouvelle Ecole"
            obj.slug = obj.slug or "nouvelle"
            obj.is_active = True
            obj.created_at = datetime.now()

        mock_db.refresh.side_effect = _fake_refresh

        response = admin_client.post("/api/v1/schools", json={
            "name": "Nouvelle Ecole",
            "slug": "nouvelle",
        })

        assert response.status_code == 201
        assert response.json()["name"] == "Nouvelle Ecole"
        assert response.json()["slug"] == "nouvelle"

    def test_direction_cannot_create(self, direction_client):
        """DIRECTION ne peut pas creer d'ecole → 403."""
        response = direction_client.post("/api/v1/schools", json={
            "name": "Test",
            "slug": "test",
        })

        assert response.status_code == 403

    def test_teacher_cannot_create(self, teacher_client):
        """TEACHER ne peut pas creer d'ecole → 403."""
        response = teacher_client.post("/api/v1/schools", json={
            "name": "Test",
            "slug": "test",
        })

        assert response.status_code == 403

    def test_duplicate_slug_409(self, admin_client, mock_db):
        """Slug duplique → 409 Conflict."""
        from sqlalchemy.exc import IntegrityError

        mock_db.commit.side_effect = IntegrityError("dup", {}, Exception())

        response = admin_client.post("/api/v1/schools", json={
            "name": "Test",
            "slug": "existant",
        })

        assert response.status_code == 409
        assert "déjà utilisé" in response.json()["detail"]

    def test_invalid_slug_422(self, admin_client):
        """Slug avec caracteres invalides → 422."""
        response = admin_client.post("/api/v1/schools", json={
            "name": "Test",
            "slug": "INVALID SLUG!",
        })

        assert response.status_code == 422

    def test_slug_too_short_422(self, admin_client):
        """Slug d'un seul caractere → 422."""
        response = admin_client.post("/api/v1/schools", json={
            "name": "Test",
            "slug": "a",
        })

        assert response.status_code == 422
