"""
Tests unitaires pour le service d'envoi de QR codes par email (US 1.6).

Scénarios couverts :
- Génération QR image (format PNG valide)
- Génération token_uid (format QRD-XXXXXXXX, unicité)
- Voyage introuvable / archivé → ValueError
- Élève sans email → no_email_count
- Élève avec QR_DIGITAL existant → already_sent_count (skip)
- Élève avec NFC physique mais PAS de QR_DIGITAL → QR envoyé (double assignation autorisée)
- Envoi réussi → assignation créée après succès email
- Erreur SMTP → loguée, pas d'assignation
- Mix d'élèves (sans email, déjà QR, NFC+envoi, nouveau)
- Voyage sans participants → résultat vide
"""

import uuid
from datetime import date
from unittest.mock import MagicMock, patch

import pytest

from app.models.assignment import Assignment
from app.models.student import Student
from app.models.trip import Trip
from app.services.qr_email_service import (
    _generate_token_uid,
    generate_qr_image,
    send_qr_emails_for_trip,
)


# ----------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------

def make_trip(status="PLANNED"):
    trip = MagicMock(spec=Trip)
    trip.id = uuid.uuid4()
    trip.destination = "Paris"
    trip.date = date(2026, 2, 22)
    trip.status = status
    return trip


def make_student(email="parent@example.com", first_name="Alice", last_name="Dupont"):
    student = MagicMock(spec=Student)
    student.id = uuid.uuid4()
    student.first_name = first_name
    student.last_name = last_name
    student.email = email
    return student


def _scalar_result(value):
    m = MagicMock()
    m.scalar.return_value = value
    return m


def _scalars_result(values):
    m = MagicMock()
    m.scalars.return_value.all.return_value = values
    return m


def make_db(trip=None, students=None, existing_digital_per_student=None):
    """
    Mock de session DB pour send_qr_emails_for_trip.
    existing_digital_per_student : liste de valeurs scalaires (None ou Assignment mock)
    correspondant à la vérification QR_DIGITAL existant pour chaque élève avec email.
    """
    db = MagicMock()

    trip_result = _scalar_result(trip)
    students_result = _scalars_result(students or [])

    assignment_results = []
    for existing in (existing_digital_per_student or []):
        assignment_results.append(_scalar_result(existing))

    db.execute.side_effect = [trip_result, students_result] + assignment_results
    return db


# ============================================================
# Tests utilitaires — génération QR
# ============================================================

def test_generate_qr_image_retourne_png():
    """La génération d'image QR doit retourner des bytes PNG valides."""
    result = generate_qr_image("QRD-ABC12345")
    assert isinstance(result, bytes)
    assert len(result) > 0
    assert result[:4] == b"\x89PNG"


def test_generate_token_uid_format():
    """L'UID généré doit respecter le format QRD-XXXXXXXX (12 caractères)."""
    uid = _generate_token_uid()
    assert uid.startswith("QRD-")
    assert len(uid) == 12
    assert uid[4:].isalnum()


def test_generate_token_uid_unique():
    """Deux appels successifs doivent produire des UIDs différents."""
    assert _generate_token_uid() != _generate_token_uid()


# ============================================================
# Tests cas d'erreur — voyage
# ============================================================

def test_voyage_introuvable():
    """Voyage inexistant → ValueError."""
    db = make_db(trip=None)
    with pytest.raises(ValueError, match="introuvable"):
        send_qr_emails_for_trip(db, uuid.uuid4())


def test_voyage_archive():
    """Voyage archivé → ValueError."""
    trip = make_trip(status="ARCHIVED")
    db = make_db(trip=trip)
    with pytest.raises(ValueError, match="archivé"):
        send_qr_emails_for_trip(db, trip.id)


# ============================================================
# Tests cas métier — skip et envoi
# ============================================================

def test_eleve_sans_email():
    """Élève sans email → no_email_count incrémenté, aucun envoi."""
    trip = make_trip()
    student = make_student(email=None)
    db = make_db(trip=trip, students=[student], existing_digital_per_student=[])

    with patch("app.services.qr_email_service.send_qr_code_email") as mock_send:
        result = send_qr_emails_for_trip(db, trip.id)

    assert result.no_email_count == 1
    assert result.sent_count == 0
    mock_send.assert_not_called()


def test_eleve_avec_qr_digital_existant_skip():
    """Élève avec QR_DIGITAL actif → already_sent_count, pas de nouvel envoi."""
    trip = make_trip()
    student = make_student()
    existing_qr = MagicMock(spec=Assignment)
    existing_qr.assignment_type = "QR_DIGITAL"
    db = make_db(trip=trip, students=[student], existing_digital_per_student=[existing_qr])

    with patch("app.services.qr_email_service.send_qr_code_email") as mock_send:
        result = send_qr_emails_for_trip(db, trip.id)

    assert result.already_sent_count == 1
    assert result.sent_count == 0
    mock_send.assert_not_called()


def test_eleve_avec_nfc_mais_pas_qr_digital_recoit_envoi():
    """
    Élève avec NFC physique mais PAS de QR_DIGITAL → QR envoyé.
    C'est le cas clé de la double assignation : un élève avec un bracelet
    physique doit quand même recevoir son QR digital de backup.
    """
    trip = make_trip()
    student = make_student()
    # La vérification QR_DIGITAL retourne None → pas encore de digital
    db = make_db(trip=trip, students=[student], existing_digital_per_student=[None])

    with patch("app.services.qr_email_service.send_qr_code_email") as mock_send:
        with patch("app.services.qr_email_service.generate_qr_image", return_value=b"FAKE_PNG"):
            result = send_qr_emails_for_trip(db, trip.id)

    assert result.sent_count == 1
    assert result.already_sent_count == 0
    mock_send.assert_called_once()
    db.add.assert_called_once()


def test_envoi_succes_cree_assignation():
    """Happy path : email envoyé → assignation QR_DIGITAL créée, commit."""
    trip = make_trip()
    student = make_student()
    db = make_db(trip=trip, students=[student], existing_digital_per_student=[None])

    with patch("app.services.qr_email_service.send_qr_code_email") as mock_send:
        with patch("app.services.qr_email_service.generate_qr_image", return_value=b"FAKE_PNG"):
            result = send_qr_emails_for_trip(db, trip.id)

    assert result.sent_count == 1
    assert result.errors == []
    mock_send.assert_called_once_with(
        to_email=student.email,
        student_name=f"{student.first_name} {student.last_name}",
        trip_destination=trip.destination,
        trip_date=trip.date,
        qr_image_bytes=b"FAKE_PNG",
    )
    db.add.assert_called_once()
    added = db.add.call_args[0][0]
    assert isinstance(added, Assignment)
    assert added.assignment_type == "QR_DIGITAL"
    db.commit.assert_called_once()


def test_erreur_smtp():
    """Erreur SMTP → erreur loguée, pas d'assignation créée."""
    trip = make_trip()
    student = make_student()
    db = make_db(trip=trip, students=[student], existing_digital_per_student=[None])

    with patch("app.services.qr_email_service.send_qr_code_email", side_effect=Exception("Connection refused")):
        with patch("app.services.qr_email_service.generate_qr_image", return_value=b"FAKE_PNG"):
            result = send_qr_emails_for_trip(db, trip.id)

    assert result.sent_count == 0
    assert len(result.errors) == 1
    assert "Connection refused" in result.errors[0]
    db.add.assert_not_called()
    db.commit.assert_called_once()  # commit final même sans assignation


def test_voyage_sans_participants():
    """Voyage sans participants → résultat vide, aucun envoi."""
    trip = make_trip()
    db = make_db(trip=trip, students=[], existing_digital_per_student=[])

    result = send_qr_emails_for_trip(db, trip.id)

    assert result.sent_count == 0
    assert result.already_sent_count == 0
    assert result.no_email_count == 0
    assert result.errors == []
    db.commit.assert_called_once()


# ============================================================
# Test mix d'élèves
# ============================================================

def test_mix_4_eleves():
    """
    Mix de 4 cas :
    - s1: sans email → no_email_count
    - s2: QR_DIGITAL existant → already_sent_count
    - s3: NFC existant mais PAS de QR_DIGITAL → envoi réussi (double assignation)
    - s4: aucune assignation → envoi réussi
    """
    trip = make_trip()
    s1 = make_student(email=None, first_name="SansEmail")
    s2 = make_student(email="deja@test.be", first_name="DejaQR")
    s3 = make_student(email="nfc@test.be", first_name="AvecNFC")
    s4 = make_student(email="new@test.be", first_name="Nouveau")

    existing_qr = MagicMock(spec=Assignment)
    existing_qr.assignment_type = "QR_DIGITAL"

    db = MagicMock()
    trip_result = _scalar_result(trip)
    students_result = _scalars_result([s1, s2, s3, s4])

    # s1 n'a pas d'email → pas de check d'assignation
    # s2 → QR_DIGITAL existe
    # s3 → pas de QR_DIGITAL (NFC n'est plus vérifié)
    # s4 → pas de QR_DIGITAL
    db.execute.side_effect = [
        trip_result,
        students_result,
        _scalar_result(existing_qr),  # s2: QR_DIGITAL existant
        _scalar_result(None),          # s3: pas de QR_DIGITAL
        _scalar_result(None),          # s4: pas de QR_DIGITAL
    ]

    with patch("app.services.qr_email_service.send_qr_code_email"):
        with patch("app.services.qr_email_service.generate_qr_image", return_value=b"PNG"):
            result = send_qr_emails_for_trip(db, trip.id)

    assert result.no_email_count == 1    # s1
    assert result.already_sent_count == 1  # s2
    assert result.sent_count == 2        # s3 + s4
    assert result.errors == []
    assert db.add.call_count == 2  # 2 assignations créées
