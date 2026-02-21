"""
Tests d'intégration API pour le bundle offline (US 2.1).
Endpoint : GET /api/v1/trips/{trip_id}/offline-data
"""

import uuid
from datetime import date, datetime, timezone
from unittest.mock import patch

from app.schemas.offline import (
    OfflineAssignment,
    OfflineCheckpoint,
    OfflineDataBundle,
    OfflineStudent,
    OfflineTripInfo,
)


# --- Helper ---

def make_bundle(trip_id=None) -> OfflineDataBundle:
    tid = trip_id or uuid.uuid4()
    return OfflineDataBundle(
        trip=OfflineTripInfo(
            id=tid,
            destination="Paris",
            date=date(2026, 3, 15),
            description="Voyage scolaire",
            status="PLANNED",
        ),
        students=[
            OfflineStudent(
                id=uuid.uuid4(),
                first_name="Alice",
                last_name="Dupont",
                assignment=OfflineAssignment(
                    token_uid="ST-001",
                    assignment_type="NFC_PHYSICAL",
                ),
            ),
            OfflineStudent(
                id=uuid.uuid4(),
                first_name="Bob",
                last_name="Martin",
                assignment=None,
            ),
        ],
        checkpoints=[
            OfflineCheckpoint(
                id=uuid.uuid4(),
                name="Départ bus",
                sequence_order=1,
                status="DRAFT",
            )
        ],
        generated_at=datetime.now(timezone.utc),
    )


# ============================================================
# GET /api/v1/trips/{trip_id}/offline-data
# ============================================================

def test_offline_data_succes(client):
    """Bundle complet → 200 avec toutes les sections."""
    trip_id = uuid.uuid4()
    with patch("app.routers.trips.offline_service.get_offline_data") as mock:
        mock.return_value = make_bundle(trip_id=trip_id)
        response = client.get(f"/api/v1/trips/{trip_id}/offline-data")

    assert response.status_code == 200
    data = response.json()
    assert data["trip"]["destination"] == "Paris"
    assert len(data["students"]) == 2
    assert data["students"][0]["assignment"]["token_uid"] == "ST-001"
    assert data["students"][1]["assignment"] is None
    assert len(data["checkpoints"]) == 1
    assert "generated_at" in data


def test_offline_data_voyage_introuvable(client):
    """Voyage inexistant → 404."""
    trip_id = uuid.uuid4()
    with patch("app.routers.trips.offline_service.get_offline_data") as mock:
        mock.side_effect = ValueError("Voyage introuvable.")
        response = client.get(f"/api/v1/trips/{trip_id}/offline-data")

    assert response.status_code == 404
    assert "introuvable" in response.json()["detail"]


def test_offline_data_voyage_archive(client):
    """Voyage archivé → 400."""
    trip_id = uuid.uuid4()
    with patch("app.routers.trips.offline_service.get_offline_data") as mock:
        mock.side_effect = ValueError(
            "Les données offline ne sont pas disponibles pour un voyage archivé."
        )
        response = client.get(f"/api/v1/trips/{trip_id}/offline-data")

    assert response.status_code == 400
    assert "archivé" in response.json()["detail"]


def test_offline_data_uuid_invalide(client):
    """UUID malformé → 422."""
    response = client.get("/api/v1/trips/pas-un-uuid/offline-data")
    assert response.status_code == 422


def test_offline_data_sans_eleves(client):
    """Bundle avec 0 élèves et 0 checkpoints → 200 avec listes vides."""
    trip_id = uuid.uuid4()
    bundle = OfflineDataBundle(
        trip=OfflineTripInfo(
            id=trip_id,
            destination="Bruges",
            date=date(2026, 4, 10),
            description=None,
            status="PLANNED",
        ),
        students=[],
        checkpoints=[],
        generated_at=datetime.now(timezone.utc),
    )
    with patch("app.routers.trips.offline_service.get_offline_data") as mock:
        mock.return_value = bundle
        response = client.get(f"/api/v1/trips/{trip_id}/offline-data")

    assert response.status_code == 200
    assert response.json()["students"] == []
    assert response.json()["checkpoints"] == []
