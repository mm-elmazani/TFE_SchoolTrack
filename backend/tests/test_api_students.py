"""
Tests d'intégration API pour la liste des élèves (US 1.3).
Testent l'endpoint GET /api/v1/students.
"""

import uuid
from datetime import datetime
from unittest.mock import MagicMock, patch

from app.models.student import Student


# --- Helpers ---

def make_student(**kwargs) -> Student:
    """Crée un mock d'élève SQLAlchemy."""
    s = MagicMock(spec=Student)
    s.id = kwargs.get("id", uuid.uuid4())
    s.first_name = kwargs.get("first_name", "Jean")
    s.last_name = kwargs.get("last_name", "Dupont")
    s.email = kwargs.get("email", None)
    s.created_at = kwargs.get("created_at", datetime.now())
    return s


# --- Tests GET /api/v1/students ---

class TestListStudents:
    def test_liste_vide(self, client):
        """Retourne 200 avec liste vide si aucun élève en BDD."""
        db_mock = MagicMock()
        db_mock.execute.return_value.scalars.return_value.all.return_value = []
        from app.database import get_db
        from app.main import app
        app.dependency_overrides[get_db] = lambda: db_mock
        resp = client.get("/api/v1/students")
        app.dependency_overrides.clear()

        assert resp.status_code == 200
        assert resp.json() == []

    def test_liste_avec_eleves(self, client):
        """Retourne 200 avec la liste des élèves triés."""
        s1 = make_student(first_name="Jean", last_name="Dupont", email="j.dupont@test.be")
        s2 = make_student(first_name="Marie", last_name="Martin", email=None)

        db_mock = MagicMock()
        db_mock.execute.return_value.scalars.return_value.all.return_value = [s1, s2]
        from app.database import get_db
        from app.main import app
        app.dependency_overrides[get_db] = lambda: db_mock

        resp = client.get("/api/v1/students")
        app.dependency_overrides.clear()

        assert resp.status_code == 200
        data = resp.json()
        assert len(data) == 2
        assert data[0]["last_name"] == "Dupont"
        assert data[0]["first_name"] == "Jean"
        assert data[0]["email"] == "j.dupont@test.be"
        assert data[1]["last_name"] == "Martin"
        assert data[1]["email"] is None

    def test_champs_requis_presents(self, client):
        """Vérifie que la réponse contient les champs id, first_name, last_name, email, created_at."""
        s = make_student(first_name="Alice", last_name="Bernard", email="a.bernard@test.be")

        db_mock = MagicMock()
        db_mock.execute.return_value.scalars.return_value.all.return_value = [s]
        from app.database import get_db
        from app.main import app
        app.dependency_overrides[get_db] = lambda: db_mock

        resp = client.get("/api/v1/students")
        app.dependency_overrides.clear()

        assert resp.status_code == 200
        item = resp.json()[0]
        assert "id" in item
        assert "first_name" in item
        assert "last_name" in item
        assert "email" in item
        assert "created_at" in item

    def test_email_null_accepte(self, client):
        """Un élève sans email retourne email: null dans le JSON."""
        s = make_student(first_name="Paul", last_name="Leroy", email=None)

        db_mock = MagicMock()
        db_mock.execute.return_value.scalars.return_value.all.return_value = [s]
        from app.database import get_db
        from app.main import app
        app.dependency_overrides[get_db] = lambda: db_mock

        resp = client.get("/api/v1/students")
        app.dependency_overrides.clear()

        assert resp.status_code == 200
        assert resp.json()[0]["email"] is None

    def test_post_body_vide_retourne_422(self, client):
        """POST sur /students avec body vide → 422 (champs obligatoires manquants)."""
        resp = client.post("/api/v1/students", json={})
        assert resp.status_code == 422
