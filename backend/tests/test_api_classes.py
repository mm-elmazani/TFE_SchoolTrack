"""
Tests d'intégration API pour les classes scolaires (US 1.3).
Testent les URLs, les codes HTTP, la validation et le format des réponses.
"""

import uuid
from datetime import datetime
from unittest.mock import patch

from app.schemas.school_class import ClassResponse


# --- Helper ---

def make_class_response(**kwargs) -> ClassResponse:
    return ClassResponse(
        id=kwargs.get("id", uuid.uuid4()),
        name=kwargs.get("name", "TI-BAC3"),
        year=kwargs.get("year", "2025-2026"),
        nb_students=kwargs.get("nb_students", 0),
        nb_teachers=kwargs.get("nb_teachers", 0),
        created_at=datetime.now(),
        updated_at=datetime.now(),
    )


# ============================================================
# POST /api/v1/classes
# ============================================================

def test_create_class_succes(client):
    """Création d'une classe valide → 201."""
    with patch("app.routers.classes.class_service.create_class") as mock:
        mock.return_value = make_class_response(name="TI-BAC3")

        response = client.post("/api/v1/classes", json={"name": "TI-BAC3", "year": "2025-2026"})

    assert response.status_code == 201
    assert response.json()["name"] == "TI-BAC3"
    assert response.json()["nb_students"] == 0
    assert response.json()["nb_teachers"] == 0


def test_create_class_nom_vide(client):
    """Nom vide → 422."""
    response = client.post("/api/v1/classes", json={"name": "   "})
    assert response.status_code == 422


def test_create_class_nom_duplique(client):
    """Nom déjà existant → 409 Conflict."""
    with patch("app.routers.classes.class_service.create_class") as mock:
        mock.side_effect = ValueError("Une classe avec le nom 'TI-BAC3' existe déjà.")

        response = client.post("/api/v1/classes", json={"name": "TI-BAC3"})

    assert response.status_code == 409
    assert "existe déjà" in response.json()["detail"]


def test_create_class_body_manquant(client):
    """Requête sans body → 422."""
    response = client.post("/api/v1/classes")
    assert response.status_code == 422


# ============================================================
# GET /api/v1/classes
# ============================================================

def test_list_classes_succes(client):
    """Liste des classes → 200 avec tableau."""
    with patch("app.routers.classes.class_service.get_classes") as mock:
        mock.return_value = [make_class_response(), make_class_response()]
        response = client.get("/api/v1/classes")

    assert response.status_code == 200
    assert len(response.json()) == 2
    assert "nb_students" in response.json()[0]
    assert "nb_teachers" in response.json()[0]


def test_list_classes_vide(client):
    """Aucune classe → 200 avec tableau vide."""
    with patch("app.routers.classes.class_service.get_classes") as mock:
        mock.return_value = []
        response = client.get("/api/v1/classes")

    assert response.status_code == 200
    assert response.json() == []


# ============================================================
# GET /api/v1/classes/{class_id}
# ============================================================

def test_get_class_succes(client):
    """Classe existante → 200."""
    class_id = uuid.uuid4()
    with patch("app.routers.classes.class_service.get_class") as mock:
        mock.return_value = make_class_response(id=class_id, name="6ème A")
        response = client.get(f"/api/v1/classes/{class_id}")

    assert response.status_code == 200
    assert response.json()["id"] == str(class_id)
    assert response.json()["name"] == "6ème A"


def test_get_class_introuvable(client):
    """Classe inexistante → 404."""
    with patch("app.routers.classes.class_service.get_class") as mock:
        mock.return_value = None
        response = client.get(f"/api/v1/classes/{uuid.uuid4()}")

    assert response.status_code == 404


# ============================================================
# PUT /api/v1/classes/{class_id}
# ============================================================

def test_update_class_succes(client):
    """Modification du nom → 200."""
    class_id = uuid.uuid4()
    with patch("app.routers.classes.class_service.update_class") as mock:
        mock.return_value = make_class_response(id=class_id, name="6ème B")
        response = client.put(f"/api/v1/classes/{class_id}", json={"name": "6ème B"})

    assert response.status_code == 200
    assert response.json()["name"] == "6ème B"


def test_update_class_introuvable(client):
    """Modifier une classe inexistante → 404."""
    with patch("app.routers.classes.class_service.update_class") as mock:
        mock.return_value = None
        response = client.put(f"/api/v1/classes/{uuid.uuid4()}", json={"name": "X"})

    assert response.status_code == 404


# ============================================================
# DELETE /api/v1/classes/{class_id}
# ============================================================

def test_delete_class_succes(client):
    """Supprimer une classe sans voyage actif → 204."""
    with patch("app.routers.classes.class_service.delete_class") as mock:
        mock.return_value = True
        response = client.delete(f"/api/v1/classes/{uuid.uuid4()}")

    assert response.status_code == 204
    assert response.content == b""


def test_delete_class_introuvable(client):
    """Supprimer une classe inexistante → 404."""
    with patch("app.routers.classes.class_service.delete_class") as mock:
        mock.return_value = False
        response = client.delete(f"/api/v1/classes/{uuid.uuid4()}")

    assert response.status_code == 404


def test_delete_class_voyage_actif(client):
    """Supprimer une classe avec voyage actif → 409."""
    with patch("app.routers.classes.class_service.delete_class") as mock:
        mock.side_effect = ValueError("participent à un voyage planifié ou en cours")
        response = client.delete(f"/api/v1/classes/{uuid.uuid4()}")

    assert response.status_code == 409
    assert "voyage" in response.json()["detail"].lower()


# ============================================================
# POST /api/v1/classes/{class_id}/students
# ============================================================

def test_assign_students_succes(client):
    """Assigner des élèves → 200 avec nb_students mis à jour."""
    class_id = uuid.uuid4()
    with patch("app.routers.classes.class_service.assign_students") as mock:
        mock.return_value = make_class_response(id=class_id, nb_students=3)

        response = client.post(f"/api/v1/classes/{class_id}/students", json={
            "student_ids": [str(uuid.uuid4()), str(uuid.uuid4()), str(uuid.uuid4())]
        })

    assert response.status_code == 200
    assert response.json()["nb_students"] == 3


def test_assign_students_liste_vide(client):
    """Liste vide → 422."""
    response = client.post(f"/api/v1/classes/{uuid.uuid4()}/students", json={
        "student_ids": []
    })
    assert response.status_code == 422


def test_assign_students_classe_introuvable(client):
    """Assigner des élèves à une classe inexistante → 404."""
    with patch("app.routers.classes.class_service.assign_students") as mock:
        mock.side_effect = ValueError("Classe introuvable.")
        response = client.post(f"/api/v1/classes/{uuid.uuid4()}/students", json={
            "student_ids": [str(uuid.uuid4())]
        })

    assert response.status_code == 404


# ============================================================
# DELETE /api/v1/classes/{class_id}/students/{student_id}
# ============================================================

def test_remove_student_succes(client):
    """Retirer un élève → 204."""
    with patch("app.routers.classes.class_service.remove_student") as mock:
        mock.return_value = True
        response = client.delete(f"/api/v1/classes/{uuid.uuid4()}/students/{uuid.uuid4()}")

    assert response.status_code == 204


def test_remove_student_lien_inexistant(client):
    """Retirer un élève non assigné → 404."""
    with patch("app.routers.classes.class_service.remove_student") as mock:
        mock.return_value = False
        response = client.delete(f"/api/v1/classes/{uuid.uuid4()}/students/{uuid.uuid4()}")

    assert response.status_code == 404


# ============================================================
# POST /api/v1/classes/{class_id}/teachers
# ============================================================

def test_assign_teachers_succes(client):
    """Assigner des enseignants → 200."""
    class_id = uuid.uuid4()
    with patch("app.routers.classes.class_service.assign_teachers") as mock:
        mock.return_value = make_class_response(id=class_id, nb_teachers=2)

        response = client.post(f"/api/v1/classes/{class_id}/teachers", json={
            "teacher_ids": [str(uuid.uuid4()), str(uuid.uuid4())]
        })

    assert response.status_code == 200
    assert response.json()["nb_teachers"] == 2


def test_assign_teachers_liste_vide(client):
    """Liste vide → 422."""
    response = client.post(f"/api/v1/classes/{uuid.uuid4()}/teachers", json={
        "teacher_ids": []
    })
    assert response.status_code == 422


# ============================================================
# GET /api/v1/classes/{class_id}/students
# ============================================================

def test_list_class_students_retourne_ids(client):
    """Retourne la liste des UUIDs des élèves assignés à une classe."""
    from unittest.mock import MagicMock
    from app.database import get_db
    from app.main import app

    student_id_1 = uuid.uuid4()
    student_id_2 = uuid.uuid4()

    db_mock = MagicMock()
    db_mock.execute.return_value.scalars.return_value.all.return_value = [
        student_id_1, student_id_2
    ]
    app.dependency_overrides[get_db] = lambda: db_mock

    class_id = uuid.uuid4()
    response = client.get(f"/api/v1/classes/{class_id}/students")
    app.dependency_overrides.clear()

    assert response.status_code == 200
    data = response.json()
    assert len(data) == 2
    assert str(student_id_1) in data
    assert str(student_id_2) in data


def test_list_class_students_vide(client):
    """Retourne une liste vide si aucun élève dans la classe."""
    from unittest.mock import MagicMock
    from app.database import get_db
    from app.main import app

    db_mock = MagicMock()
    db_mock.execute.return_value.scalars.return_value.all.return_value = []
    app.dependency_overrides[get_db] = lambda: db_mock

    response = client.get(f"/api/v1/classes/{uuid.uuid4()}/students")
    app.dependency_overrides.clear()

    assert response.status_code == 200
    assert response.json() == []
