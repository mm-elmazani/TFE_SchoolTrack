"""
Tests unitaires pour le service d'envoi de QR codes par email (US 1.6).
Couverture : génération QR image, génération token_uid, orchestration complète.
"""

import uuid
import pytest
from datetime import date
from unittest.mock import MagicMock, patch

from app.services.qr_email_service import (
    _generate_token_uid,
    generate_qr_image,
    send_qr_emails_for_trip,
)
from app.models.trip import Trip
from app.models.student import Student
from app.models.assignment import Assignment


# --- Helpers ---

def make_trip(status="PLANNED"):
    trip = MagicMock(spec=Trip)
    trip.id = uuid.uuid4()
    trip.destination = "Paris"
    trip.date = date(2026, 2, 22)
    trip.status = status
    return trip


def make_student(email="parent@example.com"):
    student = MagicMock(spec=Student)
    student.id = uuid.uuid4()
    student.first_name = "Alice"
    student.last_name = "Dupont"
    student.email = email
    return student


def make_db(trip=None, students=None, existing_assignments=None):
    """
    Crée un mock de session DB.
    existing_assignments : liste de valeurs retournées par .scalar()
    pour chaque appel de vérification d'assignment existant (une par élève).
    """
    db = MagicMock()

    trip_result = MagicMock()
    trip_result.scalar.return_value = trip

    students_result = MagicMock()
    students_result.scalars.return_value.all.return_value = students or []

    # Chaque appel de vérification d'assignement existant retourne la valeur correspondante
    assignment_results = []
    for existing in (existing_assignments or []):
        mock = MagicMock()
        mock.scalar.return_value = existing
        assignment_results.append(mock)

    db.execute.side_effect = [trip_result, students_result] + assignment_results
    return db


# ============================================================
# Tests utilitaires
# ============================================================

def test_generate_qr_image_retourne_bytes():
    """La génération d'image QR doit retourner des bytes non vides (PNG valide)."""
    result = generate_qr_image("QRD-ABC12345")
    assert isinstance(result, bytes)
    assert len(result) > 0
    # Signature PNG : 8 premiers octets
    assert result[:4] == b"\x89PNG"


def test_generate_token_uid_format():
    """L'UID généré doit respecter le format QRD-XXXXXXXX (12 caractères)."""
    uid = _generate_token_uid()
    assert uid.startswith("QRD-")
    assert len(uid) == 12
    assert uid[4:].isupper() or uid[4:].isalnum()


def test_generate_token_uid_unique():
    """Deux appels successifs doivent produire des UIDs différents."""
    assert _generate_token_uid() != _generate_token_uid()


# ============================================================
# Tests send_qr_emails_for_trip — cas d'erreur
# ============================================================

def test_voyage_introuvable():
    """Voyage inexistant → ValueError avec 'introuvable'."""
    db = make_db(trip=None, students=[])
    with pytest.raises(ValueError, match="introuvable"):
        send_qr_emails_for_trip(db, uuid.uuid4())


def test_voyage_archive():
    """Voyage archivé → ValueError avec 'archivé'."""
    trip = make_trip(status="ARCHIVED")
    db = make_db(trip=trip, students=[])
    with pytest.raises(ValueError, match="archivé"):
        send_qr_emails_for_trip(db, trip.id)


# ============================================================
# Tests send_qr_emails_for_trip — cas métier
# ============================================================

def test_eleve_sans_email():
    """Élève sans email → no_email_count incrémenté, aucun envoi."""
    trip = make_trip()
    student = make_student(email=None)
    db = make_db(trip=trip, students=[student], existing_assignments=[])

    with patch("app.services.qr_email_service.send_qr_code_email") as mock_send:
        result = send_qr_emails_for_trip(db, trip.id)

    assert result.no_email_count == 1
    assert result.sent_count == 0
    assert result.errors == []
    mock_send.assert_not_called()


def test_eleve_deja_assigne():
    """Élève avec QR_DIGITAL actif existant → already_sent_count incrémenté, aucun nouvel envoi."""
    trip = make_trip()
    student = make_student()
    existing = MagicMock(spec=Assignment)
    db = make_db(trip=trip, students=[student], existing_assignments=[existing])

    with patch("app.services.qr_email_service.send_qr_code_email") as mock_send:
        result = send_qr_emails_for_trip(db, trip.id)

    assert result.already_sent_count == 1
    assert result.sent_count == 0
    assert result.errors == []
    mock_send.assert_not_called()


def test_envoi_succes():
    """Happy path : email envoyé avec succès → sent_count++, assignation créée, commit."""
    trip = make_trip()
    student = make_student()
    db = make_db(trip=trip, students=[student], existing_assignments=[None])

    with patch("app.services.qr_email_service.send_qr_code_email") as mock_send:
        with patch("app.services.qr_email_service.generate_qr_image", return_value=b"FAKE_PNG"):
            result = send_qr_emails_for_trip(db, trip.id)

    assert result.sent_count == 1
    assert result.already_sent_count == 0
    assert result.no_email_count == 0
    assert result.errors == []
    mock_send.assert_called_once_with(
        to_email=student.email,
        student_name=f"{student.first_name} {student.last_name}",
        trip_destination=trip.destination,
        trip_date=trip.date,
        qr_image_bytes=b"FAKE_PNG",
    )
    db.add.assert_called_once()
    db.commit.assert_called_once()


def test_erreur_smtp():
    """Erreur SMTP → erreur loguée dans result.errors, pas d'assignation créée."""
    trip = make_trip()
    student = make_student()
    db = make_db(trip=trip, students=[student], existing_assignments=[None])

    with patch("app.services.qr_email_service.send_qr_code_email", side_effect=Exception("Connection refused")):
        with patch("app.services.qr_email_service.generate_qr_image", return_value=b"FAKE_PNG"):
            result = send_qr_emails_for_trip(db, trip.id)

    assert result.sent_count == 0
    assert len(result.errors) == 1
    assert "Connection refused" in result.errors[0]
    db.add.assert_not_called()
    db.commit.assert_called_once()  # commit appelé même sans assignation


def test_mix_eleves():
    """
    Mix de cas : 1 sans email, 1 déjà assigné, 1 envoi réussi.
    Vérifie que les compteurs sont corrects.
    """
    trip = make_trip()
    s_no_email = make_student(email=None)
    s_already = make_student(email="already@test.com")
    s_new = make_student(email="new@test.com")

    db = MagicMock()

    trip_result = MagicMock()
    trip_result.scalar.return_value = trip

    students_result = MagicMock()
    students_result.scalars.return_value.all.return_value = [s_no_email, s_already, s_new]

    existing_result = MagicMock()
    existing_result.scalar.return_value = MagicMock()  # s_already a déjà un QR

    new_result = MagicMock()
    new_result.scalar.return_value = None  # s_new n'a pas encore de QR

    db.execute.side_effect = [trip_result, students_result, existing_result, new_result]

    with patch("app.services.qr_email_service.send_qr_code_email"):
        with patch("app.services.qr_email_service.generate_qr_image", return_value=b"PNG"):
            result = send_qr_emails_for_trip(db, trip.id)

    assert result.no_email_count == 1
    assert result.already_sent_count == 1
    assert result.sent_count == 1
    assert result.errors == []
    db.add.assert_called_once()
