"""
Tests unitaires pour le service de génération du bundle offline (US 2.1).
"""

import uuid
import pytest
from datetime import date
from unittest.mock import MagicMock

from app.models.assignment import Assignment
from app.models.checkpoint import Checkpoint
from app.models.student import Student
from app.models.trip import Trip
from app.services.offline_service import get_offline_data


# --- Helpers ---

def make_trip(status="PLANNED"):
    t = MagicMock(spec=Trip)
    t.id = uuid.uuid4()
    t.destination = "Paris"
    t.date = date(2026, 3, 15)
    t.description = "Voyage scolaire"
    t.status = status
    return t


def make_student(first_name="Alice", last_name="Dupont"):
    s = MagicMock(spec=Student)
    s.id = uuid.uuid4()
    s.first_name = first_name
    s.last_name = last_name
    return s


def make_assignment(token_uid="ST-001", assignment_type="NFC_PHYSICAL"):
    a = MagicMock(spec=Assignment)
    a.token_uid = token_uid
    a.assignment_type = assignment_type
    return a


def make_checkpoint(name="Départ", sequence_order=1, status="DRAFT"):
    cp = MagicMock(spec=Checkpoint)
    cp.id = uuid.uuid4()
    cp.name = name
    cp.sequence_order = sequence_order
    cp.status = status
    return cp


def make_db(trip=None, student_rows=None, checkpoints=None):
    """
    Construit un mock de session DB.
    student_rows : liste de tuples (Student, Assignment|None)
    checkpoints  : liste de Checkpoint
    """
    db = MagicMock()

    trip_result = MagicMock()
    trip_result.scalar.return_value = trip

    students_result = MagicMock()
    students_result.all.return_value = student_rows or []

    checkpoints_result = MagicMock()
    checkpoints_result.scalars.return_value.all.return_value = checkpoints or []

    db.execute.side_effect = [trip_result, students_result, checkpoints_result]
    return db


# ============================================================
# Cas d'erreur
# ============================================================

def test_voyage_introuvable():
    """Voyage inexistant → ValueError."""
    db = make_db(trip=None)
    with pytest.raises(ValueError, match="introuvable"):
        get_offline_data(db, uuid.uuid4())


def test_voyage_archive():
    """Voyage archivé → ValueError."""
    trip = make_trip(status="ARCHIVED")
    db = make_db(trip=trip)
    with pytest.raises(ValueError, match="archivé"):
        get_offline_data(db, trip.id)


# ============================================================
# Bundle vide (voyage sans élèves ni checkpoints)
# ============================================================

def test_bundle_voyage_sans_eleves():
    """Voyage sans élèves → students=[], checkpoints=[]."""
    trip = make_trip()
    db = make_db(trip=trip, student_rows=[], checkpoints=[])

    result = get_offline_data(db, trip.id)

    assert result.trip.id == trip.id
    assert result.trip.destination == "Paris"
    assert result.students == []
    assert result.checkpoints == []
    assert result.generated_at is not None


# ============================================================
# Élèves sans assignation
# ============================================================

def test_eleves_sans_assignation():
    """Élèves inscrits mais sans bracelet → assignment=None."""
    trip = make_trip()
    s = make_student()
    db = make_db(trip=trip, student_rows=[(s, None)], checkpoints=[])

    result = get_offline_data(db, trip.id)

    assert len(result.students) == 1
    assert result.students[0].id == s.id
    assert result.students[0].first_name == "Alice"
    assert result.students[0].assignment is None


# ============================================================
# Élèves avec assignation
# ============================================================

def test_eleves_avec_assignation_nfc():
    """Élève avec bracelet NFC → assignment présent avec token_uid."""
    trip = make_trip()
    s = make_student()
    a = make_assignment(token_uid="ST-042", assignment_type="NFC_PHYSICAL")
    db = make_db(trip=trip, student_rows=[(s, a)], checkpoints=[])

    result = get_offline_data(db, trip.id)

    assert result.students[0].assignment is not None
    assert result.students[0].assignment.token_uid == "ST-042"
    assert result.students[0].assignment.assignment_type == "NFC_PHYSICAL"


def test_eleves_avec_assignation_qr_digital():
    """Élève avec QR digital → assignment_type=QR_DIGITAL."""
    trip = make_trip()
    s = make_student()
    a = make_assignment(token_uid="QRD-A1B2C3D4", assignment_type="QR_DIGITAL")
    db = make_db(trip=trip, student_rows=[(s, a)], checkpoints=[])

    result = get_offline_data(db, trip.id)

    assert result.students[0].assignment.assignment_type == "QR_DIGITAL"
    assert result.students[0].assignment.token_uid == "QRD-A1B2C3D4"


# ============================================================
# Checkpoints
# ============================================================

def test_checkpoints_presents():
    """Checkpoints existants → retournés dans le bon ordre."""
    trip = make_trip()
    cp1 = make_checkpoint(name="Départ bus", sequence_order=1, status="CLOSED")
    cp2 = make_checkpoint(name="Entrée musée", sequence_order=2, status="ACTIVE")
    db = make_db(trip=trip, student_rows=[], checkpoints=[cp1, cp2])

    result = get_offline_data(db, trip.id)

    assert len(result.checkpoints) == 2
    assert result.checkpoints[0].name == "Départ bus"
    assert result.checkpoints[0].sequence_order == 1
    assert result.checkpoints[0].status == "CLOSED"
    assert result.checkpoints[1].sequence_order == 2


# ============================================================
# Bundle complet
# ============================================================

def test_bundle_complet():
    """Mix : voyage + 2 élèves (1 avec assignation, 1 sans) + 1 checkpoint."""
    trip = make_trip(status="ACTIVE")
    s1 = make_student("Alice", "Dupont")
    s2 = make_student("Bob", "Martin")
    a1 = make_assignment(token_uid="ST-001", assignment_type="NFC_PHYSICAL")
    cp = make_checkpoint(name="Visite", sequence_order=1)

    db = make_db(
        trip=trip,
        student_rows=[(s1, a1), (s2, None)],
        checkpoints=[cp],
    )

    result = get_offline_data(db, trip.id)

    assert result.trip.status == "ACTIVE"
    assert len(result.students) == 2
    assert result.students[0].assignment is not None
    assert result.students[1].assignment is None
    assert len(result.checkpoints) == 1
    assert result.checkpoints[0].name == "Visite"
