"""
Tests unitaires pour le service dashboard (US 4.2).
"""

import uuid
from datetime import date, datetime
from unittest.mock import MagicMock

from app.services import dashboard_service


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _make_trip(trip_id=None, destination="Bruges", trip_date=None, status="ACTIVE"):
    trip = MagicMock()
    trip.id = trip_id or uuid.uuid4()
    trip.destination = destination
    trip.date = trip_date or date(2026, 3, 15)
    trip.status = status
    trip.created_at = datetime(2026, 3, 1)
    trip.updated_at = datetime(2026, 3, 1)
    return trip


def _make_checkpoint(cp_id=None, trip_id=None, name="CP1", seq=1, status="ACTIVE"):
    cp = MagicMock()
    cp.id = cp_id or uuid.uuid4()
    cp.trip_id = trip_id
    cp.name = name
    cp.sequence_order = seq
    cp.status = status
    cp.created_at = datetime(2026, 3, 15, 8, 0)
    cp.closed_at = datetime(2026, 3, 15, 9, 0) if status == "CLOSED" else None
    return cp


def _setup_empty_db():
    """DB mock retournant aucun voyage."""
    db = MagicMock()
    # trips query
    mock_scalars = MagicMock()
    mock_scalars.all.return_value = []
    mock_result = MagicMock()
    mock_result.scalars.return_value = mock_scalars
    db.execute.return_value = mock_result
    return db


def _setup_db_with_trips(trips, student_counts, present_counts, checkpoints_with_present, scan_rows):
    """
    Configure un mock DB pour retourner les donnees dans le bon ordre :
    1. trips, 2. student_counts, 3. present_counts, 4. checkpoints, 5. scan_rows
    """
    db = MagicMock()

    # 1. Trips (scalars().all())
    mock_trips_scalars = MagicMock()
    mock_trips_scalars.all.return_value = trips
    mock_trips_result = MagicMock()
    mock_trips_result.scalars.return_value = mock_trips_scalars

    # 2. Student counts (all())
    mock_sc = MagicMock()
    mock_sc.all.return_value = student_counts

    # 3. Present counts (all())
    mock_pc = MagicMock()
    mock_pc.all.return_value = present_counts

    # 4. Checkpoints with present (all())
    mock_cp = MagicMock()
    mock_cp.all.return_value = checkpoints_with_present

    # 5. Scan rows (all())
    mock_scan = MagicMock()
    mock_scan.all.return_value = scan_rows

    db.execute.side_effect = [mock_trips_result, mock_sc, mock_pc, mock_cp, mock_scan]
    return db


# ============================================================
# Tests
# ============================================================


class TestGetDashboardOverview:

    def test_empty_no_trips(self):
        """Aucun voyage → tout a zero."""
        db = _setup_empty_db()
        result = dashboard_service.get_dashboard_overview(db)

        assert result.total_trips == 0
        assert result.active_trips == 0
        assert result.total_students == 0
        assert result.total_attendances == 0
        assert result.global_attendance_rate == 0.0
        assert result.trips == []

    def test_single_active_trip(self):
        """Un voyage ACTIVE avec eleves et presences."""
        trip = _make_trip(status="ACTIVE")
        cp = _make_checkpoint(trip_id=trip.id, name="Depart", seq=1, status="CLOSED")

        db = _setup_db_with_trips(
            trips=[trip],
            student_counts=[(trip.id, 10)],
            present_counts=[(trip.id, 7)],
            checkpoints_with_present=[(cp, 7)],
            scan_rows=[("NFC", 5), ("QR_PHYSICAL", 2)],
        )

        result = dashboard_service.get_dashboard_overview(db)

        assert result.total_trips == 1
        assert result.active_trips == 1
        assert result.planned_trips == 0
        assert result.total_students == 10
        assert result.global_attendance_rate == 70.0
        assert len(result.trips) == 1

        ts = result.trips[0]
        assert ts.destination == "Bruges"
        assert ts.total_students == 10
        assert ts.total_present == 7
        assert ts.attendance_rate == 70.0
        assert ts.total_checkpoints == 1
        assert ts.closed_checkpoints == 1
        assert ts.last_checkpoint is not None
        assert ts.last_checkpoint.name == "Depart"

    def test_multiple_trips_mixed_status(self):
        """Plusieurs voyages avec statuts differents."""
        t1 = _make_trip(status="ACTIVE", destination="Bruges")
        t2 = _make_trip(status="PLANNED", destination="Anvers")
        t3 = _make_trip(status="COMPLETED", destination="Gand")

        db = _setup_db_with_trips(
            trips=[t1, t2, t3],
            student_counts=[(t1.id, 10), (t2.id, 5), (t3.id, 8)],
            present_counts=[(t1.id, 7), (t3.id, 8)],
            checkpoints_with_present=[],
            scan_rows=[("NFC", 10), ("MANUAL", 5)],
        )

        result = dashboard_service.get_dashboard_overview(db)

        assert result.total_trips == 3
        assert result.active_trips == 1
        assert result.planned_trips == 1
        assert result.completed_trips == 1
        assert result.total_students == 23
        assert result.total_attendances == 15

    def test_attendance_rate_zero_students(self):
        """Voyage sans eleves → taux a 0, pas de division par zero."""
        trip = _make_trip(status="ACTIVE")

        db = _setup_db_with_trips(
            trips=[trip],
            student_counts=[],  # pas d'eleves
            present_counts=[],
            checkpoints_with_present=[],
            scan_rows=[],
        )

        result = dashboard_service.get_dashboard_overview(db)

        assert result.trips[0].attendance_rate == 0.0
        assert result.global_attendance_rate == 0.0

    def test_scan_method_stats(self):
        """Repartition correcte des modes de scan."""
        trip = _make_trip(status="ACTIVE")

        db = _setup_db_with_trips(
            trips=[trip],
            student_counts=[(trip.id, 20)],
            present_counts=[(trip.id, 15)],
            checkpoints_with_present=[],
            scan_rows=[("NFC", 8), ("QR_PHYSICAL", 3), ("QR_DIGITAL", 2), ("MANUAL", 2)],
        )

        result = dashboard_service.get_dashboard_overview(db)

        assert result.scan_method_stats.nfc == 8
        assert result.scan_method_stats.qr_physical == 3
        assert result.scan_method_stats.qr_digital == 2
        assert result.scan_method_stats.manual == 2
        assert result.scan_method_stats.total == 15

    def test_checkpoint_attendance_rate(self):
        """Taux de presence par checkpoint calcule correctement."""
        trip = _make_trip(status="ACTIVE")
        cp1 = _make_checkpoint(trip_id=trip.id, name="Depart", seq=1, status="CLOSED")
        cp2 = _make_checkpoint(trip_id=trip.id, name="Arrivee", seq=2, status="ACTIVE")

        db = _setup_db_with_trips(
            trips=[trip],
            student_counts=[(trip.id, 10)],
            present_counts=[(trip.id, 8)],
            checkpoints_with_present=[(cp1, 9), (cp2, 6)],
            scan_rows=[("NFC", 15)],
        )

        result = dashboard_service.get_dashboard_overview(db)

        cps = result.trips[0].checkpoints
        assert len(cps) == 2
        assert cps[0].name == "Depart"
        assert cps[0].attendance_rate == 90.0
        assert cps[1].name == "Arrivee"
        assert cps[1].attendance_rate == 60.0

    def test_last_checkpoint_is_last_closed(self):
        """last_checkpoint = dernier checkpoint CLOSED."""
        trip = _make_trip(status="ACTIVE")
        cp1 = _make_checkpoint(trip_id=trip.id, name="CP1", seq=1, status="CLOSED")
        cp2 = _make_checkpoint(trip_id=trip.id, name="CP2", seq=2, status="CLOSED")
        cp3 = _make_checkpoint(trip_id=trip.id, name="CP3", seq=3, status="ACTIVE")

        db = _setup_db_with_trips(
            trips=[trip],
            student_counts=[(trip.id, 10)],
            present_counts=[(trip.id, 10)],
            checkpoints_with_present=[(cp1, 10), (cp2, 8), (cp3, 3)],
            scan_rows=[("NFC", 21)],
        )

        result = dashboard_service.get_dashboard_overview(db)

        assert result.trips[0].last_checkpoint.name == "CP2"
        assert result.trips[0].closed_checkpoints == 2

    def test_generated_at_present(self):
        """Le champ generated_at est renseigne."""
        db = _setup_empty_db()
        result = dashboard_service.get_dashboard_overview(db)
        assert result.generated_at is not None
