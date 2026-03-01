"""
Tests unitaires pour le service checkpoint (US 2.5 + US 2.7).
Couverture : create_checkpoint, close_checkpoint.
"""

import uuid
from datetime import datetime, timezone
from unittest.mock import MagicMock, patch

import pytest

from app.models.checkpoint import Checkpoint
from app.models.trip import Trip
from app.schemas.checkpoint import CheckpointCreate
from app.services.checkpoint_service import close_checkpoint, create_checkpoint


# ----------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------

def make_trip(status="ACTIVE"):
    t = MagicMock(spec=Trip)
    t.id = uuid.uuid4()
    t.status = status
    return t


def make_checkpoint(status="ACTIVE", checkpoint_id=None):
    cp = MagicMock(spec=Checkpoint)
    cp.id = checkpoint_id or uuid.uuid4()
    cp.trip_id = uuid.uuid4()
    cp.name = "Arrêt bus"
    cp.description = None
    cp.sequence_order = 1
    cp.status = status
    cp.created_at = datetime(2026, 5, 25, 8, 0, tzinfo=timezone.utc)
    cp.closed_at = None
    return cp


def make_db_for_create(trip=None, max_order=None):
    """DB mock pour create_checkpoint."""
    db = MagicMock()
    query_mock = MagicMock()
    db.query.return_value = query_mock
    # Premier query → Trip
    filter_trip = MagicMock()
    query_mock.filter.return_value = filter_trip
    filter_trip.first.return_value = trip
    # Deuxième query → func.max sequence_order
    scalar_mock = MagicMock()
    scalar_mock.scalar.return_value = max_order
    filter_trip.scalar.return_value = max_order
    return db


# ----------------------------------------------------------------
# create_checkpoint — US 2.5
# ----------------------------------------------------------------

class TestCreateCheckpoint:
    def test_voyage_introuvable_leve_erreur(self):
        db = MagicMock()
        db.query.return_value.filter.return_value.first.return_value = None

        with pytest.raises(ValueError, match="introuvable"):
            create_checkpoint(db, uuid.uuid4(), CheckpointCreate(name="CP"))

    def test_voyage_termine_leve_erreur(self):
        trip = make_trip(status="COMPLETED")
        db = MagicMock()
        db.query.return_value.filter.return_value.first.return_value = trip

        with pytest.raises(ValueError, match="COMPLETED"):
            create_checkpoint(db, trip.id, CheckpointCreate(name="CP"))

    def test_voyage_archive_leve_erreur(self):
        trip = make_trip(status="ARCHIVED")
        db = MagicMock()
        db.query.return_value.filter.return_value.first.return_value = trip

        with pytest.raises(ValueError, match="ARCHIVED"):
            create_checkpoint(db, trip.id, CheckpointCreate(name="CP"))

    def test_creation_reussie_commit_appele(self):
        trip = make_trip()
        db = MagicMock()
        # query(Trip).filter().first() → trip
        # query(func.max()).filter().scalar() → None
        db.query.return_value.filter.return_value.first.return_value = trip
        db.query.return_value.filter.return_value.scalar.return_value = None
        # db.refresh met à jour le checkpoint créé
        cp = make_checkpoint(status="DRAFT")
        db.refresh.side_effect = lambda obj: None

        with patch("app.services.checkpoint_service.CheckpointResponse.model_validate", return_value=cp):
            create_checkpoint(db, trip.id, CheckpointCreate(name="Entrée musée"))

        db.add.assert_called_once()
        db.commit.assert_called_once()


# ----------------------------------------------------------------
# close_checkpoint — US 2.7
# ----------------------------------------------------------------

class TestCloseCheckpoint:
    def test_checkpoint_introuvable_leve_erreur(self):
        db = MagicMock()
        db.query.return_value.filter.return_value.first.return_value = None

        with pytest.raises(ValueError, match="introuvable"):
            close_checkpoint(db, uuid.uuid4())

    def test_checkpoint_draft_leve_erreur(self):
        cp = make_checkpoint(status="DRAFT")
        db = MagicMock()
        db.query.return_value.filter.return_value.first.return_value = cp

        with pytest.raises(ValueError, match="DRAFT"):
            close_checkpoint(db, cp.id)

    def test_checkpoint_deja_closed_leve_erreur(self):
        cp = make_checkpoint(status="CLOSED")
        db = MagicMock()
        db.query.return_value.filter.return_value.first.return_value = cp

        with pytest.raises(ValueError, match="déjà clôturé"):
            close_checkpoint(db, cp.id)

    def test_checkpoint_active_passe_a_closed(self):
        cp = make_checkpoint(status="ACTIVE")
        db = MagicMock()
        db.query.return_value.filter.return_value.first.return_value = cp

        with patch("app.services.checkpoint_service.CheckpointResponse.model_validate", return_value=cp):
            close_checkpoint(db, cp.id)

        assert cp.status == "CLOSED"
        assert cp.closed_at is not None
        db.commit.assert_called_once()

    def test_closed_at_est_un_datetime_utc(self):
        cp = make_checkpoint(status="ACTIVE")
        db = MagicMock()
        db.query.return_value.filter.return_value.first.return_value = cp

        with patch("app.services.checkpoint_service.CheckpointResponse.model_validate", return_value=cp):
            close_checkpoint(db, cp.id)

        assert isinstance(cp.closed_at, datetime)
        assert cp.closed_at.tzinfo is not None
