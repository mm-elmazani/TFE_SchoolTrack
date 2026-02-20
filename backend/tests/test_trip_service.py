"""
Tests unitaires pour le service des voyages (US 1.2).
"""

import uuid
from datetime import date, timedelta
from unittest.mock import MagicMock, patch, call

import pytest
from pydantic import ValidationError

from app.schemas.trip import TripCreate, TripUpdate
from app.services.trip_service import (
    archive_trip,
    create_trip,
    get_trip,
    get_trips,
    update_trip,
)


# --- Helpers ---

def future_date(days: int = 30) -> date:
    return date.today() + timedelta(days=days)


def make_trip_mock(trip_id=None, status="PLANNED"):
    trip = MagicMock()
    trip.id = trip_id or uuid.uuid4()
    trip.destination = "Paris - Louvre"
    trip.date = future_date()
    trip.description = "Voyage test"
    trip.status = status
    trip.created_at = MagicMock()
    trip.updated_at = MagicMock()
    return trip


def make_db_mock(trip=None, student_ids=None, trip_count=0):
    db = MagicMock()

    # db.get() retourne le trip
    db.get.return_value = trip

    # db.execute() pour les scalars (student_ids ou count)
    scalar_mock = MagicMock()
    scalar_mock.scalars.return_value.all.return_value = student_ids or []
    scalar_mock.scalar.return_value = trip_count
    db.execute.return_value = scalar_mock

    return db


# --- Validation des schémas ---

def test_trip_create_date_passee_rejetee():
    """Une date dans le passé doit lever une ValidationError."""
    with pytest.raises(ValidationError) as exc:
        TripCreate(
            destination="Paris",
            date=date.today() - timedelta(days=1),
            class_ids=[uuid.uuid4()]
        )
    assert "futur" in str(exc.value).lower()


def test_trip_create_date_aujourdhui_rejetee():
    """La date d'aujourd'hui doit être rejetée (doit être strictement dans le futur)."""
    with pytest.raises(ValidationError):
        TripCreate(
            destination="Paris",
            date=date.today(),
            class_ids=[uuid.uuid4()]
        )


def test_trip_create_sans_classe_rejetee():
    """Une création sans classe doit lever une ValidationError."""
    with pytest.raises(ValidationError) as exc:
        TripCreate(
            destination="Paris",
            date=future_date(),
            class_ids=[]
        )
    assert "classe" in str(exc.value).lower()


def test_trip_create_destination_vide_rejetee():
    """Une destination vide doit être rejetée."""
    with pytest.raises(ValidationError):
        TripCreate(
            destination="   ",
            date=future_date(),
            class_ids=[uuid.uuid4()]
        )


def test_trip_update_statut_invalide_rejete():
    """Un statut inconnu dans TripUpdate doit lever une ValidationError."""
    with pytest.raises(ValidationError):
        TripUpdate(status="INEXISTANT")


def test_trip_update_statut_valide():
    """Les statuts valides doivent être acceptés."""
    for status in ["PLANNED", "ACTIVE", "COMPLETED", "ARCHIVED"]:
        update = TripUpdate(status=status)
        assert update.status == status


# --- Service create_trip ---

def test_create_trip_sans_eleves():
    """Créer un voyage sans élèves dans les classes ne doit pas planter."""
    data = TripCreate(
        destination="Rome",
        date=future_date(),
        class_ids=[uuid.uuid4()]
    )
    db = make_db_mock(student_ids=[])

    trip_mock = make_trip_mock()
    db.add = MagicMock()
    db.flush = MagicMock()
    db.commit = MagicMock()
    db.refresh = MagicMock(side_effect=lambda t: None)
    # db.get utilisé dans _to_response n'est pas appelé ici

    # On patch _to_response pour simplifier
    with patch("app.services.trip_service._to_response") as mock_resp:
        mock_resp.return_value = MagicMock()
        result = create_trip(db, data)
        assert result is not None
        db.bulk_insert_mappings.assert_not_called()


def test_create_trip_avec_eleves():
    """Les élèves des classes doivent être insérés dans trip_students."""
    student_ids = [uuid.uuid4(), uuid.uuid4(), uuid.uuid4()]
    data = TripCreate(
        destination="Berlin",
        date=future_date(),
        class_ids=[uuid.uuid4()]
    )
    db = MagicMock()
    db.execute.return_value.scalars.return_value.all.return_value = student_ids
    db.execute.return_value.scalar.return_value = len(student_ids)

    with patch("app.services.trip_service._to_response") as mock_resp:
        mock_resp.return_value = MagicMock()
        create_trip(db, data)
        db.bulk_insert_mappings.assert_called_once()
        # Vérifier que 3 mappings ont été insérés
        _, kwargs_or_args = db.bulk_insert_mappings.call_args
        mappings = db.bulk_insert_mappings.call_args[0][1]
        assert len(mappings) == 3


# --- Service get_trip ---

def test_get_trip_inexistant():
    """Un ID inexistant doit retourner None."""
    db = make_db_mock(trip=None)
    result = get_trip(db, uuid.uuid4())
    assert result is None


# --- Service archive_trip ---

def test_archive_trip_existant():
    """Archiver un voyage existant doit retourner True et changer le statut."""
    trip = make_trip_mock()
    db = make_db_mock(trip=trip)

    result = archive_trip(db, trip.id)

    assert result is True
    assert trip.status == "ARCHIVED"
    db.commit.assert_called_once()


def test_archive_trip_inexistant():
    """Archiver un voyage inexistant doit retourner False."""
    db = make_db_mock(trip=None)
    result = archive_trip(db, uuid.uuid4())
    assert result is False
    db.commit.assert_not_called()


# --- Service update_trip ---

def test_update_trip_inexistant():
    """Modifier un voyage inexistant doit retourner None."""
    db = make_db_mock(trip=None)
    result = update_trip(db, uuid.uuid4(), TripUpdate(destination="Bruxelles"))
    assert result is None


def test_update_trip_champs_partiels():
    """Seuls les champs fournis doivent être mis à jour."""
    trip = make_trip_mock()
    original_destination = trip.destination
    db = make_db_mock(trip=trip)
    db.execute.return_value.scalar.return_value = 5

    with patch("app.services.trip_service._to_response") as mock_resp:
        mock_resp.return_value = MagicMock()
        update_trip(db, trip.id, TripUpdate(status="ACTIVE"))

    # Seul le statut doit avoir changé
    assert trip.status == "ACTIVE"
    assert trip.destination == original_destination
