"""
Tests de l'envoi automatique des QR codes par email (US 1.6).
Verifie le job _send_qr_emails_scheduled et l'enregistrement du job dans le scheduler.
"""

from datetime import date, timedelta
from unittest.mock import MagicMock, patch, call

import pytest


# ============================================================
# _send_qr_emails_scheduled
# ============================================================

class TestSendQrEmailsScheduled:
    """Tests pour le job planifie d'envoi des QR codes."""

    @patch("app.scheduler.SessionLocal")
    @patch("app.services.qr_email_service.send_qr_emails_for_trip")
    def test_sends_qr_for_trips_at_j_plus_2(self, mock_send, mock_session_cls):
        """Envoie les QR pour les voyages prevus dans 2 jours."""
        from app.scheduler import _send_qr_emails_scheduled

        mock_db = MagicMock()
        mock_session_cls.return_value = mock_db

        mock_trip = MagicMock()
        mock_trip.id = "trip-001"
        mock_trip.destination = "Bruges"
        mock_trip.date = date.today() + timedelta(days=2)
        mock_db.execute.return_value.scalars.return_value.all.return_value = [mock_trip]

        _send_qr_emails_scheduled()

        mock_send.assert_called_once_with(mock_db, "trip-001")
        mock_db.close.assert_called_once()

    @patch("app.scheduler.SessionLocal")
    def test_no_trips_nothing_sent(self, mock_session_cls):
        """Pas de voyages a J+2 → aucun envoi."""
        from app.scheduler import _send_qr_emails_scheduled

        mock_db = MagicMock()
        mock_session_cls.return_value = mock_db
        mock_db.execute.return_value.scalars.return_value.all.return_value = []

        _send_qr_emails_scheduled()

        mock_db.close.assert_called_once()

    @patch("app.scheduler.SessionLocal")
    def test_exception_handled_no_crash(self, mock_session_cls):
        """Une exception pendant le processing est catchee sans crash."""
        from app.scheduler import _send_qr_emails_scheduled

        mock_db = MagicMock()
        mock_session_cls.return_value = mock_db
        mock_db.execute.side_effect = Exception("DB connection lost")

        # Ne doit pas lever d'exception
        _send_qr_emails_scheduled()

        mock_db.close.assert_called_once()


# ============================================================
# start_scheduler — job QR email
# ============================================================

class TestSchedulerQrJob:
    """Tests pour l'enregistrement du job QR email dans le scheduler."""

    @patch("app.scheduler.scheduler")
    def test_registers_qr_email_job(self, mock_scheduler):
        """start_scheduler enregistre le job qr_email_48h_check."""
        from app.scheduler import start_scheduler

        start_scheduler()

        job_ids = [c.kwargs.get("id") for c in mock_scheduler.add_job.call_args_list]
        assert "qr_email_48h_check" in job_ids

    @patch("app.scheduler.scheduler")
    def test_qr_job_interval_1h(self, mock_scheduler):
        """Le job QR email s'execute toutes les heures."""
        from app.scheduler import start_scheduler

        start_scheduler()

        qr_call = [
            c for c in mock_scheduler.add_job.call_args_list
            if c.kwargs.get("id") == "qr_email_48h_check"
        ][0]
        assert qr_call.kwargs["trigger"] == "interval"
        assert qr_call.kwargs["hours"] == 1

    @patch("app.scheduler.scheduler")
    def test_registers_trip_status_job(self, mock_scheduler):
        """start_scheduler enregistre aussi le job trip_status_auto_update."""
        from app.scheduler import start_scheduler

        start_scheduler()

        job_ids = [c.kwargs.get("id") for c in mock_scheduler.add_job.call_args_list]
        assert "trip_status_auto_update" in job_ids

    @patch("app.scheduler.scheduler")
    def test_stop_scheduler_shuts_down(self, mock_scheduler):
        """stop_scheduler arrete le scheduler s'il tourne."""
        from app.scheduler import stop_scheduler

        mock_scheduler.running = True
        stop_scheduler()

        mock_scheduler.shutdown.assert_called_once_with(wait=False)

    @patch("app.scheduler.scheduler")
    def test_stop_scheduler_noop_if_not_running(self, mock_scheduler):
        """stop_scheduler ne fait rien si le scheduler n'est pas demarre."""
        from app.scheduler import stop_scheduler

        mock_scheduler.running = False
        stop_scheduler()

        mock_scheduler.shutdown.assert_not_called()
