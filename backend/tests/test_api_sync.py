"""
Tests d'intégration API pour la synchronisation offline → online (US 3.1).
Endpoint : POST /api/sync/attendances
"""

import uuid
from unittest.mock import patch

from app.schemas.sync import SyncResponse


# --- Helper ---

def make_scan_payload(**kwargs) -> dict:
    return {
        "client_uuid": kwargs.get("client_uuid", str(uuid.uuid4())),
        "student_id": kwargs.get("student_id", str(uuid.uuid4())),
        "checkpoint_id": kwargs.get("checkpoint_id", str(uuid.uuid4())),
        "trip_id": kwargs.get("trip_id", str(uuid.uuid4())),
        "scanned_at": kwargs.get("scanned_at", "2026-02-20T14:32:15Z"),
        "scan_method": kwargs.get("scan_method", "NFC"),
    }


def make_sync_response(accepted=None, duplicate=None, received=2, inserted=2) -> SyncResponse:
    a = accepted or [str(uuid.uuid4()), str(uuid.uuid4())]
    return SyncResponse(
        accepted=a,
        duplicate=duplicate or [],
        total_received=received,
        total_inserted=inserted,
    )


# ============================================================
# POST /api/sync/attendances
# ============================================================

def test_sync_succes(client):
    """Batch valide → 200 avec rapport complet."""
    scan1 = make_scan_payload()
    scan2 = make_scan_payload(scan_method="QR_DIGITAL")

    with patch("app.routers.sync.sync_service.sync_attendances") as mock:
        mock.return_value = make_sync_response(received=2, inserted=2)
        response = client.post("/api/sync/attendances", json={
            "scans": [scan1, scan2],
            "device_id": "flutter-device-01",
        })

    assert response.status_code == 200
    data = response.json()
    assert data["total_received"] == 2
    assert data["total_inserted"] == 2
    assert data["duplicate"] == []


def test_sync_batch_vide(client):
    """Batch vide → 200 avec 0 inséré."""
    with patch("app.routers.sync.sync_service.sync_attendances") as mock:
        mock.return_value = SyncResponse(
            accepted=[], duplicate=[], total_received=0, total_inserted=0
        )
        response = client.post("/api/sync/attendances", json={"scans": []})

    assert response.status_code == 200
    assert response.json()["total_inserted"] == 0


def test_sync_avec_doublons(client):
    """Batch avec doublons → 200, doublons dans la réponse."""
    uid_dup = str(uuid.uuid4())
    with patch("app.routers.sync.sync_service.sync_attendances") as mock:
        mock.return_value = SyncResponse(
            accepted=[str(uuid.uuid4())],
            duplicate=[uid_dup],
            total_received=2,
            total_inserted=1,
        )
        response = client.post("/api/sync/attendances", json={
            "scans": [make_scan_payload(), make_scan_payload(client_uuid=uid_dup)]
        })

    assert response.status_code == 200
    data = response.json()
    assert data["total_inserted"] == 1
    assert uid_dup in data["duplicate"]


def test_sync_methode_invalide(client):
    """Méthode de scan inconnue → 422."""
    response = client.post("/api/sync/attendances", json={
        "scans": [make_scan_payload(scan_method="BLUETOOTH")]
    })
    assert response.status_code == 422


def test_sync_client_uuid_invalide(client):
    """client_uuid malformé → 422."""
    scan = make_scan_payload(client_uuid="pas-un-uuid")
    response = client.post("/api/sync/attendances", json={"scans": [scan]})
    assert response.status_code == 422


def test_sync_champ_manquant(client):
    """Scan sans checkpoint_id → 422."""
    scan = {
        "client_uuid": str(uuid.uuid4()),
        "student_id": str(uuid.uuid4()),
        # checkpoint_id manquant
        "trip_id": str(uuid.uuid4()),
        "scanned_at": "2026-02-20T14:32:15Z",
        "scan_method": "NFC",
    }
    response = client.post("/api/sync/attendances", json={"scans": [scan]})
    assert response.status_code == 422


def test_sync_batch_trop_grand(client):
    """Batch de plus de 500 scans → 422."""
    scans = [make_scan_payload() for _ in range(501)]
    response = client.post("/api/sync/attendances", json={"scans": scans})
    assert response.status_code == 422


def test_sync_sans_body(client):
    """Requête sans body → 422."""
    response = client.post("/api/sync/attendances")
    assert response.status_code == 422
