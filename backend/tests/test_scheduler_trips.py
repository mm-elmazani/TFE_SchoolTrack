"""
Tests de la transition automatique des statuts de voyages.
Verifie que les voyages PLANNED passent en ACTIVE le jour J
et que les PLANNED passes passent directement en COMPLETED (rattrapage).

NOTE : la transition ACTIVE → COMPLETED a ete supprimee (2026-04-15) —
les voyages peuvent durer plusieurs jours, la cloture est manuelle.
"""

from datetime import date, timedelta
from unittest.mock import MagicMock, patch
from uuid import uuid4


class TestAutoUpdateTripStatuses:
    """Tests pour _auto_update_trip_statuses."""

    def _make_trip(self, status, trip_date):
        """Helper : cree un mock Trip."""
        trip = MagicMock()
        trip.id = uuid4()
        trip.destination = "Bruxelles"
        trip.status = status
        trip.date = trip_date
        return trip

    @patch("app.services.assignment_service.release_trip_tokens")
    @patch("app.scheduler.SessionLocal")
    def test_planned_to_active_today(self, mock_session_cls, mock_assign):
        """PLANNED + date == aujourd'hui → ACTIVE."""
        from app.scheduler import _auto_update_trip_statuses

        trip = self._make_trip("PLANNED", date.today())
        mock_db = MagicMock()
        mock_session_cls.return_value = mock_db
        mock_db.execute.return_value.scalars.return_value.all.side_effect = [
            [trip],  # planned today
            [],      # planned past
        ]

        _auto_update_trip_statuses()

        assert trip.status == "ACTIVE"
        mock_db.commit.assert_called_once()
        mock_db.close.assert_called_once()

    @patch("app.services.assignment_service.release_trip_tokens")
    @patch("app.scheduler.SessionLocal")
    def test_active_reste_active(self, mock_session_cls, mock_assign):
        """ACTIVE + date < aujourd'hui → reste ACTIVE (pas de cloture auto)."""
        from app.scheduler import _auto_update_trip_statuses

        trip = self._make_trip("ACTIVE", date.today() - timedelta(days=1))
        mock_db = MagicMock()
        mock_session_cls.return_value = mock_db
        mock_db.execute.return_value.scalars.return_value.all.side_effect = [
            [],  # planned today
            [],  # planned past (ACTIVE pas concerne)
        ]

        _auto_update_trip_statuses()

        # Le statut ne doit pas changer
        assert trip.status == "ACTIVE"
        # Aucune liberation de bracelets
        mock_assign.assert_not_called()
        mock_db.commit.assert_called_once()
        mock_db.close.assert_called_once()

    @patch("app.services.assignment_service.release_trip_tokens")
    @patch("app.scheduler.SessionLocal")
    def test_planned_past_to_completed(self, mock_session_cls, mock_assign):
        """PLANNED + date < aujourd'hui → COMPLETED (rattrapage) + liberation bracelets."""
        from app.scheduler import _auto_update_trip_statuses

        trip = self._make_trip("PLANNED", date.today() - timedelta(days=10))
        mock_db = MagicMock()
        mock_session_cls.return_value = mock_db
        mock_db.execute.return_value.scalars.return_value.all.side_effect = [
            [],      # planned today
            [trip],  # planned past
        ]

        _auto_update_trip_statuses()

        assert trip.status == "COMPLETED"
        mock_assign.assert_called_once_with(mock_db, trip.id)
        mock_db.commit.assert_called_once()
        mock_db.close.assert_called_once()

    @patch("app.services.assignment_service.release_trip_tokens")
    @patch("app.scheduler.SessionLocal")
    def test_no_trips_to_update(self, mock_session_cls, mock_assign):
        """Aucun voyage a mettre a jour → pas de changement."""
        from app.scheduler import _auto_update_trip_statuses

        mock_db = MagicMock()
        mock_session_cls.return_value = mock_db
        mock_db.execute.return_value.scalars.return_value.all.side_effect = [
            [],  # planned today
            [],  # planned past
        ]

        _auto_update_trip_statuses()

        mock_db.commit.assert_called_once()
        mock_assign.assert_not_called()
        mock_db.close.assert_called_once()

    @patch("app.services.assignment_service.release_trip_tokens")
    @patch("app.scheduler.SessionLocal")
    def test_multiple_trips_mixed(self, mock_session_cls, mock_assign):
        """Plusieurs voyages PLANNED mixtes (today + past)."""
        from app.scheduler import _auto_update_trip_statuses

        planned_today = self._make_trip("PLANNED", date.today())
        planned_past = self._make_trip("PLANNED", date.today() - timedelta(days=20))

        mock_db = MagicMock()
        mock_session_cls.return_value = mock_db
        mock_db.execute.return_value.scalars.return_value.all.side_effect = [
            [planned_today],   # planned today
            [planned_past],    # planned past
        ]

        _auto_update_trip_statuses()

        assert planned_today.status == "ACTIVE"
        assert planned_past.status == "COMPLETED"
        # release_trip_tokens appele uniquement pour planned_past
        assert mock_assign.call_count == 1

    @patch("app.services.assignment_service.release_trip_tokens")
    @patch("app.scheduler.SessionLocal")
    def test_handles_exception(self, mock_session_cls, mock_assign):
        """Erreur DB → rollback, pas de crash."""
        from app.scheduler import _auto_update_trip_statuses

        mock_db = MagicMock()
        mock_session_cls.return_value = mock_db
        mock_db.execute.side_effect = Exception("DB error")

        # Ne doit pas lever d'exception
        _auto_update_trip_statuses()

        mock_db.rollback.assert_called_once()
        mock_db.close.assert_called_once()

    @patch("app.scheduler.scheduler")
    def test_scheduler_registers_trip_status_job(self, mock_scheduler):
        """Verifie que le job est enregistre au demarrage."""
        from app.scheduler import start_scheduler

        start_scheduler()

        job_ids = [c.kwargs.get("id") for c in mock_scheduler.add_job.call_args_list]
        assert "trip_status_auto_update" in job_ids

        # Verifie interval 15 minutes
        trip_call = [c for c in mock_scheduler.add_job.call_args_list
                     if c.kwargs.get("id") == "trip_status_auto_update"][0]
        assert trip_call.kwargs["trigger"] == "interval"
        assert trip_call.kwargs["minutes"] == 15
