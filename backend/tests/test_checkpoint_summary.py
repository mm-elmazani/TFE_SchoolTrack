"""
Tests US 4.4 — Timeline et résumé checkpoints.
Service get_checkpoints_summary + endpoint GET /api/v1/trips/{trip_id}/checkpoints-summary.
"""

import uuid
from datetime import datetime, timedelta
from unittest.mock import MagicMock, patch

import pytest

from app.models.user import User
from app.schemas.checkpoint import CheckpointsSummary, CheckpointTimelineEntry
from app.services.checkpoint_service import get_checkpoints_summary


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _make_trip(**kwargs):
    trip = MagicMock()
    trip.id = kwargs.get("id", uuid.uuid4())
    trip.destination = kwargs.get("destination", "Bruges")
    trip.status = kwargs.get("status", "ACTIVE")
    return trip


def _make_checkpoint(**kwargs):
    cp = MagicMock()
    cp.id = kwargs.get("id", uuid.uuid4())
    cp.trip_id = kwargs.get("trip_id", uuid.uuid4())
    cp.name = kwargs.get("name", "Arrêt bus")
    cp.description = kwargs.get("description", None)
    cp.sequence_order = kwargs.get("sequence_order", 1)
    cp.status = kwargs.get("status", "ACTIVE")
    cp.created_at = kwargs.get("created_at", datetime(2026, 3, 1, 8, 0))
    cp.started_at = kwargs.get("started_at", None)
    cp.closed_at = kwargs.get("closed_at", None)
    cp.created_by = kwargs.get("created_by", None)
    return cp


def _make_summary(**kwargs) -> CheckpointsSummary:
    return CheckpointsSummary(
        trip_id=kwargs.get("trip_id", uuid.uuid4()),
        trip_destination=kwargs.get("trip_destination", "Bruges"),
        total_checkpoints=kwargs.get("total_checkpoints", 2),
        active_checkpoints=kwargs.get("active_checkpoints", 1),
        closed_checkpoints=kwargs.get("closed_checkpoints", 1),
        total_scans=kwargs.get("total_scans", 5),
        avg_duration_minutes=kwargs.get("avg_duration_minutes", 30.0),
        timeline=kwargs.get("timeline", []),
    )


# ============================================================
# Service — get_checkpoints_summary
# ============================================================


class TestGetCheckpointsSummaryService:
    """Tests unitaires du service get_checkpoints_summary."""

    def test_trip_introuvable(self):
        """Voyage introuvable → ValueError."""
        db = MagicMock()
        db.query.return_value.filter.return_value.first.return_value = None

        with pytest.raises(ValueError, match="introuvable"):
            get_checkpoints_summary(db, uuid.uuid4())

    def test_aucun_checkpoint(self):
        """Voyage sans checkpoints → résumé vide."""
        db = MagicMock()
        trip = _make_trip()
        db.query.return_value.filter.return_value.first.return_value = trip
        db.query.return_value.filter.return_value.order_by.return_value.all.return_value = []

        result = get_checkpoints_summary(db, trip.id)

        assert result.total_checkpoints == 0
        assert result.timeline == []
        assert result.total_scans == 0

    def test_avec_checkpoints(self):
        """Checkpoints avec scans → résumé complet."""
        db = MagicMock()
        trip = _make_trip()
        cp1_id = uuid.uuid4()
        cp2_id = uuid.uuid4()
        user_id = uuid.uuid4()

        cp1 = _make_checkpoint(
            id=cp1_id, trip_id=trip.id, name="Départ",
            sequence_order=1, status="CLOSED",
            started_at=datetime(2026, 3, 1, 8, 0),
            closed_at=datetime(2026, 3, 1, 8, 30),
            created_by=user_id,
        )
        cp2 = _make_checkpoint(
            id=cp2_id, trip_id=trip.id, name="Musée",
            sequence_order=2, status="ACTIVE",
            started_at=datetime(2026, 3, 1, 9, 0),
        )

        user_mock = MagicMock()
        user_mock.id = user_id
        user_mock.first_name = "Jean"
        user_mock.last_name = "Dupont"
        user_mock.email = "jean@test.be"

        # Configuration des queries chaînées
        query_mock = MagicMock()
        trip_filter = MagicMock()
        trip_filter.first.return_value = trip
        checkpoint_filter = MagicMock()
        checkpoint_order = MagicMock()
        checkpoint_order.all.return_value = [cp1, cp2]
        checkpoint_filter.order_by.return_value = checkpoint_order

        # scan_counts query
        scan_filter = MagicMock()
        scan_filter.group_by.return_value.all.return_value = [(cp1_id, 3), (cp2_id, 2)]

        # student_counts query
        student_filter = MagicMock()
        student_filter.group_by.return_value.all.return_value = [(cp1_id, 3), (cp2_id, 2)]

        # users query
        user_filter = MagicMock()
        user_filter.all.return_value = [user_mock]

        call_count = [0]
        filter_results = [trip_filter, checkpoint_filter, scan_filter, student_filter, user_filter]

        def side_effect_query(*args):
            mock_q = MagicMock()
            def filter_side(*fargs, **fkwargs):
                idx = call_count[0]
                call_count[0] += 1
                return filter_results[idx]
            mock_q.filter.side_effect = filter_side
            return mock_q

        db.query.side_effect = side_effect_query

        result = get_checkpoints_summary(db, trip.id)

        assert result.total_checkpoints == 2
        assert result.active_checkpoints == 1
        assert result.closed_checkpoints == 1
        assert result.total_scans == 5
        assert result.avg_duration_minutes == 30.0
        assert len(result.timeline) == 2
        assert result.timeline[0].name == "Départ"
        assert result.timeline[0].scan_count == 3
        assert result.timeline[0].created_by_name == "Jean Dupont"
        assert result.timeline[0].duration_minutes == 30

    def test_sans_createur(self):
        """Checkpoint sans created_by → created_by_name est None."""
        db = MagicMock()
        trip = _make_trip()
        cp = _make_checkpoint(id=uuid.uuid4(), trip_id=trip.id, created_by=None)

        query_mock = MagicMock()
        trip_filter = MagicMock()
        trip_filter.first.return_value = trip
        cp_filter = MagicMock()
        cp_filter.order_by.return_value.all.return_value = [cp]

        scan_filter = MagicMock()
        scan_filter.group_by.return_value.all.return_value = []

        student_filter = MagicMock()
        student_filter.group_by.return_value.all.return_value = []

        call_count = [0]
        filter_results = [trip_filter, cp_filter, scan_filter, student_filter]

        def side_effect_query(*args):
            mock_q = MagicMock()
            def filter_side(*fargs, **fkwargs):
                idx = call_count[0]
                call_count[0] += 1
                return filter_results[idx]
            mock_q.filter.side_effect = filter_side
            return mock_q

        db.query.side_effect = side_effect_query

        result = get_checkpoints_summary(db, trip.id)

        assert result.timeline[0].created_by_name is None

    def test_duree_non_calculee_si_pas_closed(self):
        """Checkpoint ACTIVE (pas de closed_at) → duration_minutes None."""
        db = MagicMock()
        trip = _make_trip()
        cp = _make_checkpoint(
            id=uuid.uuid4(), trip_id=trip.id,
            started_at=datetime(2026, 3, 1, 8, 0),
            closed_at=None,
            status="ACTIVE",
        )

        trip_filter = MagicMock()
        trip_filter.first.return_value = trip
        cp_filter = MagicMock()
        cp_filter.order_by.return_value.all.return_value = [cp]
        scan_filter = MagicMock()
        scan_filter.group_by.return_value.all.return_value = []
        student_filter = MagicMock()
        student_filter.group_by.return_value.all.return_value = []

        call_count = [0]
        filter_results = [trip_filter, cp_filter, scan_filter, student_filter]

        def side_effect_query(*args):
            mock_q = MagicMock()
            def filter_side(*fargs, **fkwargs):
                idx = call_count[0]
                call_count[0] += 1
                return filter_results[idx]
            mock_q.filter.side_effect = filter_side
            return mock_q

        db.query.side_effect = side_effect_query

        result = get_checkpoints_summary(db, trip.id)

        assert result.timeline[0].duration_minutes is None
        assert result.avg_duration_minutes is None


# ============================================================
# API — GET /api/v1/trips/{trip_id}/checkpoints-summary
# ============================================================


class TestCheckpointsSummaryEndpoint:
    """Tests d'intégration de l'endpoint checkpoints-summary."""

    def test_summary_succes(self, client):
        """Voyage avec checkpoints → 200 + résumé complet."""
        trip_id = uuid.uuid4()
        with patch("app.routers.checkpoints.checkpoint_service.get_checkpoints_summary") as mock:
            mock.return_value = _make_summary(trip_id=trip_id, total_checkpoints=3)

            response = client.get(f"/api/v1/trips/{trip_id}/checkpoints-summary")

        assert response.status_code == 200
        data = response.json()
        assert data["total_checkpoints"] == 3
        assert data["trip_id"] == str(trip_id)

    def test_summary_voyage_introuvable(self, client):
        """Voyage introuvable → 404."""
        trip_id = uuid.uuid4()
        with patch("app.routers.checkpoints.checkpoint_service.get_checkpoints_summary") as mock:
            mock.side_effect = ValueError(f"Voyage {trip_id} introuvable.")

            response = client.get(f"/api/v1/trips/{trip_id}/checkpoints-summary")

        assert response.status_code == 404
        assert "introuvable" in response.json()["detail"]

    def test_summary_voyage_vide(self, client):
        """Voyage sans checkpoints → 200 avec total=0."""
        trip_id = uuid.uuid4()
        with patch("app.routers.checkpoints.checkpoint_service.get_checkpoints_summary") as mock:
            mock.return_value = _make_summary(
                trip_id=trip_id, total_checkpoints=0,
                active_checkpoints=0, closed_checkpoints=0,
                total_scans=0, avg_duration_minutes=None,
            )

            response = client.get(f"/api/v1/trips/{trip_id}/checkpoints-summary")

        assert response.status_code == 200
        assert response.json()["total_checkpoints"] == 0

    def test_summary_avec_timeline(self, client):
        """Résumé avec timeline → champs checkpoint correctement sérialisés."""
        trip_id = uuid.uuid4()
        entry = CheckpointTimelineEntry(
            id=uuid.uuid4(), name="Départ gare", sequence_order=1,
            status="CLOSED", scan_count=5, student_count=20,
            duration_minutes=15, created_by_name="Jean Dupont",
        )
        with patch("app.routers.checkpoints.checkpoint_service.get_checkpoints_summary") as mock:
            mock.return_value = _make_summary(trip_id=trip_id, timeline=[entry])

            response = client.get(f"/api/v1/trips/{trip_id}/checkpoints-summary")

        data = response.json()
        assert len(data["timeline"]) == 1
        assert data["timeline"][0]["name"] == "Départ gare"
        assert data["timeline"][0]["scan_count"] == 5
        assert data["timeline"][0]["duration_minutes"] == 15
        assert data["timeline"][0]["created_by_name"] == "Jean Dupont"

    def test_summary_trip_id_invalide(self, client):
        """trip_id non-UUID → 422."""
        response = client.get("/api/v1/trips/pas-un-uuid/checkpoints-summary")
        assert response.status_code == 422

    def test_summary_non_admin_interdit(self, client):
        """Enseignant → 403 (route réservée direction)."""
        from app.dependencies import get_current_user
        from app.main import app

        teacher = MagicMock(spec=User)
        teacher.id = uuid.uuid4()
        teacher.role = "TEACHER"
        teacher.email = "t@schooltrack.be"
        teacher.is_2fa_enabled = False
        teacher.totp_secret = None

        app.dependency_overrides[get_current_user] = lambda: teacher

        trip_id = uuid.uuid4()
        response = client.get(f"/api/v1/trips/{trip_id}/checkpoints-summary")
        assert response.status_code == 403
