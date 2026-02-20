"""
Tests unitaires pour le service d'assignation de bracelets (US 1.5).
"""

import uuid
from datetime import datetime
from unittest.mock import MagicMock, patch

import pytest
from pydantic import ValidationError

from app.schemas.assignment import AssignmentCreate, AssignmentReassign
from app.services.assignment_service import assign_token, reassign_token


# --- Helpers ---

def make_assignment_data(**kwargs):
    return AssignmentCreate(
        token_uid=kwargs.get("token_uid", "ST-001"),
        student_id=kwargs.get("student_id", uuid.uuid4()),
        trip_id=kwargs.get("trip_id", uuid.uuid4()),
        assignment_type=kwargs.get("assignment_type", "NFC_PHYSICAL"),
    )


def make_db(is_participant=True, token_taken=False, student_taken=False):
    """Crée un mock de session avec comportement configurable."""
    db = MagicMock()
    db.add = MagicMock()
    db.commit = MagicMock()
    db.refresh = MagicMock()

    # Séquence des appels db.execute().scalar()
    results = [
        MagicMock() if is_participant else None,  # is_participant
        MagicMock() if token_taken else None,      # token_taken
        MagicMock() if student_taken else None,    # student_taken
    ]
    db.execute.return_value.scalar.side_effect = results

    # Pour _update_token_status
    db.execute.return_value.scalar.side_effect = results + [None]
    return db


# --- Validation des schémas ---

def test_assignment_type_invalide():
    with pytest.raises(ValidationError, match="Type invalide"):
        AssignmentCreate(
            token_uid="ST-001",
            student_id=uuid.uuid4(),
            trip_id=uuid.uuid4(),
            assignment_type="BLUETOOTH",
        )


def test_assignment_token_uid_vide():
    with pytest.raises(ValidationError):
        AssignmentCreate(
            token_uid="   ",
            student_id=uuid.uuid4(),
            trip_id=uuid.uuid4(),
            assignment_type="NFC_PHYSICAL",
        )


def test_assignment_token_uid_uppercase():
    """Le token_uid doit être mis en majuscules automatiquement."""
    data = AssignmentCreate(
        token_uid="st-001",
        student_id=uuid.uuid4(),
        trip_id=uuid.uuid4(),
        assignment_type="NFC_PHYSICAL",
    )
    assert data.token_uid == "ST-001"


def test_reassign_sans_justification():
    with pytest.raises(ValidationError, match="justification"):
        AssignmentReassign(
            token_uid="ST-001",
            student_id=uuid.uuid4(),
            trip_id=uuid.uuid4(),
            assignment_type="NFC_PHYSICAL",
            justification="   ",
        )


def test_reassign_types_valides():
    for t in ["NFC_PHYSICAL", "QR_PHYSICAL", "QR_DIGITAL"]:
        data = AssignmentReassign(
            token_uid="ST-001",
            student_id=uuid.uuid4(),
            trip_id=uuid.uuid4(),
            assignment_type=t,
            justification="Bracelet endommagé",
        )
        assert data.assignment_type == t


# --- assign_token ---

def test_assign_eleve_non_inscrit():
    """Un élève non inscrit au voyage doit être refusé."""
    db = MagicMock()
    db.execute.return_value.scalar.return_value = None  # pas participant

    with pytest.raises(ValueError, match="pas inscrit"):
        assign_token(db, make_assignment_data())


def test_assign_token_deja_pris():
    """Un token déjà assigné sur ce voyage doit être refusé."""
    db = MagicMock()
    db.execute.return_value.scalar.side_effect = [
        MagicMock(),  # is_participant ✓
        MagicMock(),  # token_taken ✗
    ]
    with pytest.raises(ValueError, match="déjà assigné"):
        assign_token(db, make_assignment_data())


def test_assign_eleve_deja_assigne():
    """Un élève ayant déjà un bracelet sur ce voyage doit être refusé."""
    db = MagicMock()
    db.execute.return_value.scalar.side_effect = [
        MagicMock(),  # is_participant ✓
        None,         # token libre ✓
        MagicMock(),  # student_taken ✗
    ]
    with pytest.raises(ValueError, match="déjà un bracelet"):
        assign_token(db, make_assignment_data())


def test_assign_succes():
    """Assignation valide : l'assignment est créé et committé."""
    assignment_mock = MagicMock()
    assignment_mock.id = 1
    assignment_mock.token_uid = "ST-001"
    assignment_mock.student_id = uuid.uuid4()
    assignment_mock.trip_id = uuid.uuid4()
    assignment_mock.assignment_type = "NFC_PHYSICAL"
    assignment_mock.assigned_at = datetime.now()
    assignment_mock.released_at = None

    db = MagicMock()
    db.execute.return_value.scalar.side_effect = [
        MagicMock(),  # is_participant ✓
        None,         # token libre ✓
        None,         # élève libre ✓
        None,         # _update_token_status
    ]
    db.refresh.side_effect = lambda obj: None

    with patch("app.services.assignment_service.AssignmentResponse.model_validate") as mock_resp:
        mock_resp.return_value = MagicMock()
        result = assign_token(db, make_assignment_data())

    db.add.assert_called_once()
    db.commit.assert_called_once()
    assert result is not None
