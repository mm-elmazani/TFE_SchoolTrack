"""
Tests unitaires pour le service alertes (US 4.3).
"""

import uuid
from datetime import datetime
from unittest.mock import MagicMock

import pytest

from app.schemas.alert import AlertCreate, AlertUpdate
from app.services import alert_service


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _make_trip(trip_id=None):
    trip = MagicMock()
    trip.id = trip_id or uuid.uuid4()
    trip.destination = "Bruges"
    return trip


def _make_student(student_id=None, is_deleted=False):
    s = MagicMock()
    s.id = student_id or uuid.uuid4()
    s.first_name = "Marie"
    s.last_name = "Dupont"
    s.is_deleted = is_deleted
    return s


def _make_checkpoint(cp_id=None):
    cp = MagicMock()
    cp.id = cp_id or uuid.uuid4()
    cp.name = "Depart gare"
    return cp


def _make_alert(alert_id=None, trip_id=None, student_id=None, status="ACTIVE",
                alert_type="STUDENT_MISSING", severity="HIGH"):
    a = MagicMock()
    a.id = alert_id or uuid.uuid4()
    a.trip_id = trip_id or uuid.uuid4()
    a.checkpoint_id = None
    a.student_id = student_id or uuid.uuid4()
    a.alert_type = alert_type
    a.severity = severity
    a.message = "Eleve absent"
    a.status = status
    a.created_by = None
    a.resolved_by = None
    a.created_at = datetime(2026, 3, 15, 10, 0)
    a.resolved_at = None
    return a


# ============================================================
# Tests create_alert
# ============================================================

class TestCreateAlert:

    def test_create_success(self):
        """Creation d'une alerte → succes."""
        trip = _make_trip()
        student = _make_student()

        db = MagicMock()
        db.get.side_effect = lambda model, id: {
            trip.id: trip,
            student.id: student,
        }.get(id)

        # Simuler le refresh
        def fake_refresh(obj):
            obj.id = uuid.uuid4()
            obj.created_at = datetime.now()
        db.refresh = fake_refresh

        data = AlertCreate(
            trip_id=trip.id,
            student_id=student.id,
            alert_type="STUDENT_MISSING",
            severity="HIGH",
        )

        result = alert_service.create_alert(db, data)
        assert result.alert_type == "STUDENT_MISSING"
        assert result.severity == "HIGH"
        assert result.student_name == "Dupont Marie"

    def test_create_trip_not_found(self):
        """Voyage introuvable → ValueError."""
        db = MagicMock()
        db.get.return_value = None

        data = AlertCreate(
            trip_id=uuid.uuid4(),
            student_id=uuid.uuid4(),
            alert_type="STUDENT_MISSING",
        )

        with pytest.raises(ValueError, match="Voyage introuvable"):
            alert_service.create_alert(db, data)

    def test_create_student_not_found(self):
        """Eleve introuvable → ValueError."""
        trip = _make_trip()
        db = MagicMock()
        db.get.side_effect = lambda model, id: trip if id == trip.id else None

        data = AlertCreate(
            trip_id=trip.id,
            student_id=uuid.uuid4(),
            alert_type="STUDENT_MISSING",
        )

        with pytest.raises(ValueError, match="Eleve introuvable"):
            alert_service.create_alert(db, data)


# ============================================================
# Tests update_alert_status
# ============================================================

class TestUpdateAlertStatus:

    def test_resolve_alert(self):
        """Resolution d'une alerte → resolved_at renseigne."""
        alert = _make_alert(status="ACTIVE")
        db = MagicMock()
        db.get.side_effect = lambda model, id: alert if id == alert.id else None

        # Mock enrichissement
        student = _make_student(student_id=alert.student_id)
        trip = _make_trip(trip_id=alert.trip_id)

        original_get = db.get.side_effect
        def enriched_get(model, id):
            if id == alert.id:
                return alert
            if id == alert.student_id:
                return student
            if id == alert.trip_id:
                return trip
            return None
        db.get.side_effect = enriched_get

        data = AlertUpdate(status="RESOLVED")
        user_id = uuid.uuid4()
        result = alert_service.update_alert_status(db, alert.id, data, resolved_by=user_id)

        assert alert.status == "RESOLVED"
        assert alert.resolved_by == user_id
        assert alert.resolved_at is not None

    def test_acknowledge_alert(self):
        """Prise en charge d'une alerte → IN_PROGRESS."""
        alert = _make_alert(status="ACTIVE")
        db = MagicMock()

        student = _make_student(student_id=alert.student_id)
        trip = _make_trip(trip_id=alert.trip_id)
        db.get.side_effect = lambda model, id: {
            alert.id: alert,
            alert.student_id: student,
            alert.trip_id: trip,
        }.get(id)

        data = AlertUpdate(status="IN_PROGRESS")
        result = alert_service.update_alert_status(db, alert.id, data)

        assert alert.status == "IN_PROGRESS"

    def test_alert_not_found(self):
        """Alerte introuvable → ValueError."""
        db = MagicMock()
        db.get.return_value = None

        data = AlertUpdate(status="RESOLVED")

        with pytest.raises(ValueError, match="introuvable"):
            alert_service.update_alert_status(db, uuid.uuid4(), data)


# ============================================================
# Tests get_alert_stats
# ============================================================

class TestGetAlertStats:

    def test_stats_empty(self):
        """Aucune alerte → tout a zero."""
        db = MagicMock()
        db.execute.return_value.scalar.return_value = 0

        result = alert_service.get_alert_stats(db)

        assert result.total == 0
        assert result.active == 0
        assert result.critical == 0


# ============================================================
# Tests _to_response enrichissement
# ============================================================

class TestToResponse:

    def test_deleted_student_name(self):
        """Eleve supprime → [Supprime]."""
        alert = _make_alert()
        student = _make_student(student_id=alert.student_id, is_deleted=True)
        trip = _make_trip(trip_id=alert.trip_id)

        db = MagicMock()
        db.get.side_effect = lambda model, id: {
            alert.student_id: student,
            alert.trip_id: trip,
        }.get(id)

        result = alert_service._to_response(db, alert)
        assert result.student_name == "[Supprime]"

    def test_enrichment_with_checkpoint(self):
        """Alerte avec checkpoint → nom checkpoint enrichi."""
        cp = _make_checkpoint()
        alert = _make_alert()
        alert.checkpoint_id = cp.id
        student = _make_student(student_id=alert.student_id)
        trip = _make_trip(trip_id=alert.trip_id)

        db = MagicMock()
        db.get.side_effect = lambda model, id: {
            alert.student_id: student,
            alert.trip_id: trip,
            cp.id: cp,
        }.get(id)

        result = alert_service._to_response(db, alert)
        assert result.checkpoint_name == "Depart gare"
        assert result.trip_destination == "Bruges"
