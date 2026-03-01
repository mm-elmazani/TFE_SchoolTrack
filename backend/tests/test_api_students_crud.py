"""
Tests d'intégration API pour le CRUD manuel des élèves.
POST /api/v1/students    — création
PUT  /api/v1/students/{id} — mise à jour
DELETE /api/v1/students/{id} — suppression
"""

import uuid
from datetime import datetime
from unittest.mock import MagicMock, patch

from app.models.student import Student


# --- Helpers ---

def make_student(**kwargs) -> Student:
    s = MagicMock(spec=Student)
    s.id = kwargs.get("id", uuid.uuid4())
    s.first_name = kwargs.get("first_name", "Jean")
    s.last_name = kwargs.get("last_name", "Dupont")
    s.email = kwargs.get("email", "jean.dupont@school.be")
    s.created_at = kwargs.get("created_at", datetime.now())
    return s


# ============================================================
# POST /api/v1/students
# ============================================================

def test_create_student_succes(client):
    """Création valide → 201 avec les données retournées."""
    student = make_student(first_name="Alice", last_name="Bernard", email="alice@school.be")

    with patch("app.routers.students.Student") as mock_cls:
        mock_cls.return_value = student

        response = client.post("/api/v1/students", json={
            "first_name": "Alice",
            "last_name": "Bernard",
            "email": "alice@school.be",
        })

    assert response.status_code == 201
    data = response.json()
    assert data["first_name"] == "Alice"
    assert data["last_name"] == "Bernard"
    assert data["email"] == "alice@school.be"
    assert "id" in data


def test_create_student_sans_email(client):
    """Création sans email → 201, email null."""
    student = make_student(first_name="Jean", last_name="Sans", email=None)

    with patch("app.routers.students.Student") as mock_cls:
        mock_cls.return_value = student

        response = client.post("/api/v1/students", json={
            "first_name": "Jean",
            "last_name": "Sans",
        })

    assert response.status_code == 201
    assert response.json()["email"] is None


def test_create_student_prenom_vide(client):
    """Prénom vide → 422."""
    response = client.post("/api/v1/students", json={
        "first_name": "   ",
        "last_name": "Dupont",
    })
    assert response.status_code == 422


def test_create_student_nom_vide(client):
    """Nom vide → 422."""
    response = client.post("/api/v1/students", json={
        "first_name": "Jean",
        "last_name": "",
    })
    assert response.status_code == 422


def test_create_student_email_invalide(client):
    """Email mal formé → 422."""
    response = client.post("/api/v1/students", json={
        "first_name": "Jean",
        "last_name": "Dupont",
        "email": "pas-un-email",
    })
    assert response.status_code == 422


def test_create_student_body_manquant(client):
    """Body absent → 422."""
    response = client.post("/api/v1/students")
    assert response.status_code == 422


# ============================================================
# PUT /api/v1/students/{id}
# ============================================================

def test_update_student_prenom_seul(client):
    """Mise à jour du prénom uniquement → 200, les autres champs inchangés."""
    sid = uuid.uuid4()
    student = make_student(id=sid, first_name="Jean-Pierre", last_name="Dupont")

    from app.database import get_db
    from app.main import app

    mock_db = MagicMock()
    mock_db.get.return_value = student
    app.dependency_overrides[get_db] = lambda: mock_db

    response = client.put(f"/api/v1/students/{sid}", json={"first_name": "Jean-Pierre"})

    app.dependency_overrides.clear()

    assert response.status_code == 200
    assert response.json()["first_name"] == "Jean-Pierre"
    assert response.json()["last_name"] == "Dupont"


def test_update_student_introuvable(client):
    """Élève inexistant → 404."""
    sid = uuid.uuid4()

    # On override db.get pour retourner None (élève non trouvé)
    from app.database import get_db
    from app.main import app

    mock_db = MagicMock()
    mock_db.get.return_value = None
    app.dependency_overrides[get_db] = lambda: mock_db

    response = client.put(f"/api/v1/students/{sid}", json={"first_name": "Test"})

    app.dependency_overrides.clear()

    assert response.status_code == 404
    assert "introuvable" in response.json()["detail"].lower()


def test_update_student_uuid_invalide(client):
    """UUID malformé → 422."""
    response = client.put("/api/v1/students/pas-un-uuid", json={"first_name": "Test"})
    assert response.status_code == 422


def test_update_student_nom_vide(client):
    """Nom mis à jour avec valeur vide → 422."""
    response = client.put(f"/api/v1/students/{uuid.uuid4()}", json={"last_name": ""})
    assert response.status_code == 422


def test_update_student_email_invalide(client):
    """Email mis à jour avec valeur invalide → 422."""
    response = client.put(f"/api/v1/students/{uuid.uuid4()}", json={"email": "pas-valide"})
    assert response.status_code == 422


def test_update_student_succes_complet(client):
    """Mise à jour complète d'un élève existant → 200."""
    sid = uuid.uuid4()
    student = make_student(id=sid)
    student.first_name = "Marie"
    student.last_name = "Martin"
    student.email = "marie@test.be"

    from app.database import get_db
    from app.main import app

    mock_db = MagicMock()
    mock_db.get.return_value = student
    app.dependency_overrides[get_db] = lambda: mock_db

    response = client.put(f"/api/v1/students/{sid}", json={
        "first_name": "Marie",
        "last_name": "Martin",
        "email": "marie@test.be",
    })

    app.dependency_overrides.clear()

    assert response.status_code == 200
    data = response.json()
    assert data["first_name"] == "Marie"
    assert data["last_name"] == "Martin"


# ============================================================
# DELETE /api/v1/students/{id}
# ============================================================

def test_delete_student_succes(client):
    """Suppression d'un élève existant → 204."""
    sid = uuid.uuid4()
    student = make_student(id=sid)

    from app.database import get_db
    from app.main import app

    mock_db = MagicMock()
    mock_db.get.return_value = student
    app.dependency_overrides[get_db] = lambda: mock_db

    response = client.delete(f"/api/v1/students/{sid}")

    app.dependency_overrides.clear()

    assert response.status_code == 204
    assert response.content == b""


def test_delete_student_introuvable(client):
    """Suppression d'un élève inexistant → 404."""
    sid = uuid.uuid4()

    from app.database import get_db
    from app.main import app

    mock_db = MagicMock()
    mock_db.get.return_value = None
    app.dependency_overrides[get_db] = lambda: mock_db

    response = client.delete(f"/api/v1/students/{sid}")

    app.dependency_overrides.clear()

    assert response.status_code == 404
    assert "introuvable" in response.json()["detail"].lower()


def test_delete_student_uuid_invalide(client):
    """UUID malformé → 422."""
    response = client.delete("/api/v1/students/pas-un-uuid")
    assert response.status_code == 422
