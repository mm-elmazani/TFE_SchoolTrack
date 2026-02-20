"""
Tests d'intégration API pour l'envoi des QR codes par email (US 1.6).
Endpoint : POST /api/v1/trips/{trip_id}/send-qr-emails
"""

import uuid
from unittest.mock import patch

from app.schemas.qr_email import QrEmailSendResult


# --- Helper ---

def make_result(trip_id=None, sent=2, already=1, no_email=0, errors=None) -> QrEmailSendResult:
    return QrEmailSendResult(
        trip_id=trip_id or uuid.uuid4(),
        sent_count=sent,
        already_sent_count=already,
        no_email_count=no_email,
        errors=errors or [],
    )


# ============================================================
# POST /api/v1/trips/{trip_id}/send-qr-emails
# ============================================================

def test_send_qr_emails_succes(client):
    """Envoi réussi → 200 avec le rapport complet."""
    trip_id = uuid.uuid4()
    with patch("app.routers.trips.qr_email_service.send_qr_emails_for_trip") as mock:
        mock.return_value = make_result(trip_id=trip_id, sent=5, already=2, no_email=1)
        response = client.post(f"/api/v1/trips/{trip_id}/send-qr-emails")

    assert response.status_code == 200
    data = response.json()
    assert data["sent_count"] == 5
    assert data["already_sent_count"] == 2
    assert data["no_email_count"] == 1
    assert data["errors"] == []
    assert data["trip_id"] == str(trip_id)


def test_send_qr_emails_voyage_introuvable(client):
    """Voyage inexistant → 404."""
    trip_id = uuid.uuid4()
    with patch("app.routers.trips.qr_email_service.send_qr_emails_for_trip") as mock:
        mock.side_effect = ValueError("Voyage introuvable.")
        response = client.post(f"/api/v1/trips/{trip_id}/send-qr-emails")

    assert response.status_code == 404
    assert "introuvable" in response.json()["detail"]


def test_send_qr_emails_voyage_archive(client):
    """Voyage archivé → 400."""
    trip_id = uuid.uuid4()
    with patch("app.routers.trips.qr_email_service.send_qr_emails_for_trip") as mock:
        mock.side_effect = ValueError("Impossible d'envoyer des QR codes pour un voyage archivé.")
        response = client.post(f"/api/v1/trips/{trip_id}/send-qr-emails")

    assert response.status_code == 400
    assert "archivé" in response.json()["detail"]


def test_send_qr_emails_uuid_invalide(client):
    """UUID malformé → 422."""
    response = client.post("/api/v1/trips/pas-un-uuid/send-qr-emails")
    assert response.status_code == 422


def test_send_qr_emails_avec_erreurs_smtp(client):
    """Envoi partiel avec erreurs SMTP → 200 mais erreurs présentes dans la réponse."""
    trip_id = uuid.uuid4()
    with patch("app.routers.trips.qr_email_service.send_qr_emails_for_trip") as mock:
        mock.return_value = make_result(
            trip_id=trip_id,
            sent=2,
            errors=["Erreur envoi email x@y.com : Connection refused"],
        )
        response = client.post(f"/api/v1/trips/{trip_id}/send-qr-emails")

    assert response.status_code == 200
    data = response.json()
    assert data["sent_count"] == 2
    assert len(data["errors"]) == 1
    assert "Connection refused" in data["errors"][0]
