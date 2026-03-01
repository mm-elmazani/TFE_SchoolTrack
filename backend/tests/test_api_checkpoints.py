"""
Tests d'intégration API pour les checkpoints terrain (US 2.5 + US 2.7).
Testent POST /api/v1/trips/{trip_id}/checkpoints
      POST /api/v1/checkpoints/{checkpoint_id}/close
"""

import uuid
from datetime import datetime
from unittest.mock import patch

from app.schemas.checkpoint import CheckpointResponse


# --- Helpers ---

def make_checkpoint_response(**kwargs) -> CheckpointResponse:
    return CheckpointResponse(
        id=kwargs.get("id", uuid.uuid4()),
        trip_id=kwargs.get("trip_id", uuid.uuid4()),
        name=kwargs.get("name", "Arrêt bus"),
        description=kwargs.get("description", None),
        sequence_order=kwargs.get("sequence_order", 1),
        status=kwargs.get("status", "DRAFT"),
        created_at=kwargs.get("created_at", datetime.now()),
    )


# ============================================================
# POST /api/v1/trips/{trip_id}/checkpoints
# ============================================================

def test_create_checkpoint_succes(client):
    """Création d'un checkpoint valide → 201 avec statut DRAFT."""
    trip_id = uuid.uuid4()
    with patch("app.routers.checkpoints.checkpoint_service.create_checkpoint") as mock:
        mock.return_value = make_checkpoint_response(
            trip_id=trip_id,
            name="Arrêt bus",
            sequence_order=1,
        )

        response = client.post(
            f"/api/v1/trips/{trip_id}/checkpoints",
            json={"name": "Arrêt bus"},
        )

    assert response.status_code == 201
    data = response.json()
    assert data["name"] == "Arrêt bus"
    assert data["status"] == "DRAFT"
    assert data["sequence_order"] == 1
    assert "id" in data


def test_create_checkpoint_avec_description(client):
    """Création avec description optionnelle → 201."""
    trip_id = uuid.uuid4()
    with patch("app.routers.checkpoints.checkpoint_service.create_checkpoint") as mock:
        mock.return_value = make_checkpoint_response(
            name="Entrée musée",
            description="Vérifier les billets",
        )

        response = client.post(
            f"/api/v1/trips/{trip_id}/checkpoints",
            json={"name": "Entrée musée", "description": "Vérifier les billets"},
        )

    assert response.status_code == 201
    assert response.json()["description"] == "Vérifier les billets"


def test_create_checkpoint_nom_vide(client):
    """Nom vide → 422 Unprocessable Entity."""
    trip_id = uuid.uuid4()
    response = client.post(
        f"/api/v1/trips/{trip_id}/checkpoints",
        json={"name": ""},
    )
    assert response.status_code == 422


def test_create_checkpoint_nom_espaces(client):
    """Nom composé uniquement d'espaces → 422."""
    trip_id = uuid.uuid4()
    response = client.post(
        f"/api/v1/trips/{trip_id}/checkpoints",
        json={"name": "   "},
    )
    assert response.status_code == 422


def test_create_checkpoint_voyage_introuvable(client):
    """Voyage inexistant → 404."""
    trip_id = uuid.uuid4()
    with patch("app.routers.checkpoints.checkpoint_service.create_checkpoint") as mock:
        mock.side_effect = ValueError(f"Voyage {trip_id} introuvable.")

        response = client.post(
            f"/api/v1/trips/{trip_id}/checkpoints",
            json={"name": "Arrêt 1"},
        )

    assert response.status_code == 404
    assert "introuvable" in response.json()["detail"]


def test_create_checkpoint_voyage_completed(client):
    """Voyage terminé (COMPLETED) → 400."""
    trip_id = uuid.uuid4()
    with patch("app.routers.checkpoints.checkpoint_service.create_checkpoint") as mock:
        mock.side_effect = ValueError(
            "Impossible de créer un checkpoint : le voyage est en statut COMPLETED."
        )

        response = client.post(
            f"/api/v1/trips/{trip_id}/checkpoints",
            json={"name": "Arrêt 1"},
        )

    assert response.status_code == 400


def test_create_checkpoint_voyage_archived(client):
    """Voyage archivé → 400."""
    trip_id = uuid.uuid4()
    with patch("app.routers.checkpoints.checkpoint_service.create_checkpoint") as mock:
        mock.side_effect = ValueError(
            "Impossible de créer un checkpoint : le voyage est en statut ARCHIVED."
        )

        response = client.post(
            f"/api/v1/trips/{trip_id}/checkpoints",
            json={"name": "Arrêt 1"},
        )

    assert response.status_code == 400


def test_create_checkpoint_trip_id_invalide(client):
    """trip_id non-UUID → 422."""
    response = client.post(
        "/api/v1/trips/pas-un-uuid/checkpoints",
        json={"name": "Arrêt 1"},
    )
    assert response.status_code == 422


def test_create_checkpoint_body_manquant(client):
    """Body JSON absent → 422."""
    trip_id = uuid.uuid4()
    response = client.post(f"/api/v1/trips/{trip_id}/checkpoints")
    assert response.status_code == 422


# ============================================================
# POST /api/v1/checkpoints/{checkpoint_id}/close (US 2.7)
# ============================================================

def test_close_checkpoint_succes(client):
    """Checkpoint ACTIVE → clôture réussie → 200, statut CLOSED."""
    cp_id = uuid.uuid4()
    with patch("app.routers.checkpoints.checkpoint_service.close_checkpoint") as mock:
        mock.return_value = make_checkpoint_response(id=cp_id, status="CLOSED")

        response = client.post(f"/api/v1/checkpoints/{cp_id}/close")

    assert response.status_code == 200
    assert response.json()["status"] == "CLOSED"


def test_close_checkpoint_introuvable(client):
    """Checkpoint inconnu → 404."""
    cp_id = uuid.uuid4()
    with patch("app.routers.checkpoints.checkpoint_service.close_checkpoint") as mock:
        mock.side_effect = ValueError(f"Checkpoint {cp_id} introuvable.")

        response = client.post(f"/api/v1/checkpoints/{cp_id}/close")

    assert response.status_code == 404
    assert "introuvable" in response.json()["detail"]


def test_close_checkpoint_draft(client):
    """Checkpoint DRAFT → 400."""
    with patch("app.routers.checkpoints.checkpoint_service.close_checkpoint") as mock:
        mock.side_effect = ValueError("Impossible de clôturer un checkpoint en statut DRAFT.")

        response = client.post(f"/api/v1/checkpoints/{uuid.uuid4()}/close")

    assert response.status_code == 400


def test_close_checkpoint_deja_closed(client):
    """Checkpoint déjà CLOSED → 400."""
    with patch("app.routers.checkpoints.checkpoint_service.close_checkpoint") as mock:
        mock.side_effect = ValueError("Le checkpoint est déjà clôturé.")

        response = client.post(f"/api/v1/checkpoints/{uuid.uuid4()}/close")

    assert response.status_code == 400


def test_close_checkpoint_id_invalide(client):
    """checkpoint_id non-UUID → 422."""
    response = client.post("/api/v1/checkpoints/pas-un-uuid/close")
    assert response.status_code == 422
