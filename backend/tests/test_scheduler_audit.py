"""
Tests de la rotation automatique des audit logs (US 6.4).
Verifie que les logs > 12 mois sont supprimes et les recents conserves.
"""

from datetime import datetime, timedelta
from unittest.mock import MagicMock, patch

import pytest


class TestAuditLogRotation:
    """Tests pour _purge_old_audit_logs."""

    @patch("app.scheduler.SessionLocal")
    def test_purge_deletes_old_logs(self, mock_session_cls):
        """Verifie que DELETE est execute avec la bonne date de coupure."""
        from app.scheduler import _purge_old_audit_logs

        mock_db = MagicMock()
        mock_session_cls.return_value = mock_db
        mock_db.execute.return_value.rowcount = 42

        _purge_old_audit_logs()

        # Verifie qu'un DELETE a ete execute
        mock_db.execute.assert_called_once()
        call_args = mock_db.execute.call_args
        sql_str = str(call_args[0][0])
        assert "DELETE FROM audit_logs" in sql_str
        assert "performed_at" in sql_str

        # Verifie le parametre cutoff (~365 jours)
        params = call_args[0][1]
        cutoff = params["cutoff"]
        expected = datetime.utcnow() - timedelta(days=365)
        assert abs((cutoff - expected).total_seconds()) < 5

        # Verifie commit + close
        mock_db.commit.assert_called_once()
        mock_db.close.assert_called_once()

    @patch("app.scheduler.SessionLocal")
    def test_purge_no_rows_deleted(self, mock_session_cls):
        """Verifie le comportement quand aucun log n'est a supprimer."""
        from app.scheduler import _purge_old_audit_logs

        mock_db = MagicMock()
        mock_session_cls.return_value = mock_db
        mock_db.execute.return_value.rowcount = 0

        _purge_old_audit_logs()

        mock_db.commit.assert_called_once()
        mock_db.close.assert_called_once()

    @patch("app.scheduler.SessionLocal")
    def test_purge_handles_exception(self, mock_session_cls):
        """Verifie que les erreurs sont gerees sans crash."""
        from app.scheduler import _purge_old_audit_logs

        mock_db = MagicMock()
        mock_session_cls.return_value = mock_db
        mock_db.execute.side_effect = Exception("DB error")

        # Ne doit pas lever d'exception
        _purge_old_audit_logs()

        mock_db.rollback.assert_called_once()
        mock_db.close.assert_called_once()

    @patch("app.scheduler.scheduler")
    def test_scheduler_registers_audit_job(self, mock_scheduler):
        """Verifie que le job de rotation est enregistre au demarrage."""
        from app.scheduler import start_scheduler

        start_scheduler()

        # Verifie que add_job a ete appele avec le job audit
        job_ids = [call.kwargs.get("id") for call in mock_scheduler.add_job.call_args_list]
        assert "audit_log_rotation" in job_ids

        # Verifie le trigger cron a 3h
        audit_call = [c for c in mock_scheduler.add_job.call_args_list if c.kwargs.get("id") == "audit_log_rotation"][0]
        assert audit_call.kwargs["trigger"] == "cron"
        assert audit_call.kwargs["hour"] == 3
