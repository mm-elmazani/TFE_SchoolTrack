"""
Tests d'intégration API pour les voyages (US 1.2).
Testent les URLs, les codes HTTP, la validation et le format des réponses.
"""

import uuid
from datetime import date, datetime, timedelta
from unittest.mock import patch

from app.schemas.trip import TripResponse


# --- Helpers ---

def future_date(days: int = 30) -> str:
    return (date.today() + timedelta(days=days)).isoformat()


def make_trip_response(**kwargs) -> TripResponse:
    return TripResponse(
        id=kwargs.get("id", uuid.uuid4()),
        destination=kwargs.get("destination", "Paris - Louvre"),
        date=kwargs.get("date", date.today() + timedelta(days=30)),
        description=kwargs.get("description", None),
        status=kwargs.get("status", "PLANNED"),
        total_students=kwargs.get("total_students", 5),
        created_at=datetime.now(),
        updated_at=datetime.now(),
    )


# ============================================================
# POST /api/v1/trips
# ============================================================

def test_create_trip_succes(client):
    """Création d'un voyage valide → 201 avec les données correctes."""
    with patch("app.routers.trips.trip_service.create_trip") as mock:
        mock.return_value = make_trip_response(destination="Paris - Louvre")

        response = client.post("/api/v1/trips", json={
            "destination": "Paris - Louvre",
            "date": future_date(),
            "class_ids": [str(uuid.uuid4())]
        })

    assert response.status_code == 201
    assert response.json()["destination"] == "Paris - Louvre"
    assert response.json()["status"] == "PLANNED"
    assert "id" in response.json()


def test_create_trip_date_passee(client):
    """Date dans le passé → 422 Unprocessable Entity."""
    response = client.post("/api/v1/trips", json={
        "destination": "Paris",
        "date": "2025-01-01",
        "class_ids": [str(uuid.uuid4())]
    })
    assert response.status_code == 422
    assert "futur" in response.text.lower()


def test_create_trip_date_aujourdhui(client):
    """Date d'aujourd'hui → 422 (doit être strictement dans le futur)."""
    response = client.post("/api/v1/trips", json={
        "destination": "Paris",
        "date": date.today().isoformat(),
        "class_ids": [str(uuid.uuid4())]
    })
    assert response.status_code == 422


def test_create_trip_sans_classe(client):
    """Aucune classe sélectionnée → 422."""
    response = client.post("/api/v1/trips", json={
        "destination": "Paris",
        "date": future_date(),
        "class_ids": []
    })
    assert response.status_code == 422
    assert "classe" in response.text.lower()


def test_create_trip_destination_vide(client):
    """Destination vide → 422."""
    response = client.post("/api/v1/trips", json={
        "destination": "   ",
        "date": future_date(),
        "class_ids": [str(uuid.uuid4())]
    })
    assert response.status_code == 422


def test_create_trip_body_manquant(client):
    """Requête sans body → 422."""
    response = client.post("/api/v1/trips")
    assert response.status_code == 422


# ============================================================
# GET /api/v1/trips
# ============================================================

def test_list_trips_succes(client):
    """Liste des voyages → 200 avec un tableau."""
    with patch("app.routers.trips.trip_service.get_trips") as mock:
        mock.return_value = [make_trip_response(), make_trip_response()]

        response = client.get("/api/v1/trips")

    assert response.status_code == 200
    assert isinstance(response.json(), list)
    assert len(response.json()) == 2


def test_list_trips_vide(client):
    """Aucun voyage → 200 avec tableau vide."""
    with patch("app.routers.trips.trip_service.get_trips") as mock:
        mock.return_value = []
        response = client.get("/api/v1/trips")

    assert response.status_code == 200
    assert response.json() == []


# ============================================================
# GET /api/v1/trips/{trip_id}
# ============================================================

def test_get_trip_succes(client):
    """Voyage existant → 200 avec l'ID correct."""
    trip_id = uuid.uuid4()
    with patch("app.routers.trips.trip_service.get_trip") as mock:
        mock.return_value = make_trip_response(id=trip_id)
        response = client.get(f"/api/v1/trips/{trip_id}")

    assert response.status_code == 200
    assert response.json()["id"] == str(trip_id)


def test_get_trip_introuvable(client):
    """Voyage inexistant → 404."""
    with patch("app.routers.trips.trip_service.get_trip") as mock:
        mock.return_value = None
        response = client.get(f"/api/v1/trips/{uuid.uuid4()}")

    assert response.status_code == 404


def test_get_trip_uuid_invalide(client):
    """UUID malformé → 422."""
    response = client.get("/api/v1/trips/pas-un-uuid")
    assert response.status_code == 422


# ============================================================
# PUT /api/v1/trips/{trip_id}
# ============================================================

def test_update_trip_succes(client):
    """Modification d'un voyage → 200 avec le nouveau statut."""
    trip_id = uuid.uuid4()
    with patch("app.routers.trips.trip_service.update_trip") as mock:
        mock.return_value = make_trip_response(id=trip_id, status="ACTIVE")
        response = client.put(f"/api/v1/trips/{trip_id}", json={"status": "ACTIVE"})

    assert response.status_code == 200
    assert response.json()["status"] == "ACTIVE"


def test_update_trip_introuvable(client):
    """Modifier un voyage inexistant → 404."""
    with patch("app.routers.trips.trip_service.update_trip") as mock:
        mock.return_value = None
        response = client.put(f"/api/v1/trips/{uuid.uuid4()}", json={"status": "ACTIVE"})

    assert response.status_code == 404


def test_update_trip_statut_invalide(client):
    """Statut inconnu → 422."""
    response = client.put(f"/api/v1/trips/{uuid.uuid4()}", json={"status": "INVALIDE"})
    assert response.status_code == 422


# ============================================================
# DELETE /api/v1/trips/{trip_id}
# ============================================================

def test_archive_trip_succes(client):
    """Archiver un voyage existant → 204 sans body."""
    with patch("app.routers.trips.trip_service.archive_trip") as mock:
        mock.return_value = True
        response = client.delete(f"/api/v1/trips/{uuid.uuid4()}")

    assert response.status_code == 204
    assert response.content == b""


def test_archive_trip_introuvable(client):
    """Archiver un voyage inexistant → 404."""
    with patch("app.routers.trips.trip_service.archive_trip") as mock:
        mock.return_value = False
        response = client.delete(f"/api/v1/trips/{uuid.uuid4()}")

    assert response.status_code == 404
