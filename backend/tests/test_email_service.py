"""
Tests unitaires pour le service d'envoi d'emails SMTP (US 1.6).
Verifie la construction du message MIME et l'interaction SMTP.
"""

from datetime import date
from unittest.mock import MagicMock, patch, call

import pytest


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

_FAKE_QR_BYTES = b"\x89PNG\r\n\x1a\n" + b"\x00" * 100  # Faux PNG


def _mock_settings(**overrides):
    """Cree un mock de settings avec les valeurs par defaut."""
    s = MagicMock()
    s.SMTP_HOST = overrides.get("SMTP_HOST", "smtp.example.com")
    s.SMTP_PORT = overrides.get("SMTP_PORT", 587)
    s.SMTP_USERNAME = overrides.get("SMTP_USERNAME", "user@example.com")
    s.SMTP_PASSWORD = overrides.get("SMTP_PASSWORD", "secret")
    s.SMTP_FROM = overrides.get("SMTP_FROM", "noreply@schooltrack.be")
    s.SMTP_USE_TLS = overrides.get("SMTP_USE_TLS", True)
    return s


# ============================================================
# Tests d'envoi d'email QR code
# ============================================================

class TestSendQrCodeEmail:
    """Tests pour send_qr_code_email."""

    @patch("app.services.email_service.smtplib.SMTP")
    @patch("app.services.email_service.settings", _mock_settings())
    def test_subject_contains_destination_and_date(self, mock_smtp_cls):
        """Le sujet contient la destination et la date formatee."""
        from app.services.email_service import send_qr_code_email

        mock_server = MagicMock()
        mock_smtp_cls.return_value.__enter__ = MagicMock(return_value=mock_server)
        mock_smtp_cls.return_value.__exit__ = MagicMock(return_value=False)

        send_qr_code_email(
            to_email="parent@example.com",
            student_name="Jean Dupont",
            trip_destination="Bruges",
            trip_date=date(2026, 6, 15),
            qr_image_bytes=_FAKE_QR_BYTES,
        )

        # Recuperer le message envoye
        msg = mock_server.send_message.call_args[0][0]
        assert "Bruges" in msg["Subject"]
        assert "15/06/2026" in msg["Subject"]

    @patch("app.services.email_service.smtplib.SMTP")
    @patch("app.services.email_service.settings", _mock_settings())
    def test_html_body_contains_student_info(self, mock_smtp_cls):
        """Le corps HTML contient le nom de l'eleve, la destination et la date."""
        from app.services.email_service import send_qr_code_email

        mock_server = MagicMock()
        mock_smtp_cls.return_value.__enter__ = MagicMock(return_value=mock_server)
        mock_smtp_cls.return_value.__exit__ = MagicMock(return_value=False)

        send_qr_code_email(
            to_email="parent@example.com",
            student_name="Marie Leroy",
            trip_destination="Amsterdam",
            trip_date=date(2026, 9, 1),
            qr_image_bytes=_FAKE_QR_BYTES,
        )

        msg = mock_server.send_message.call_args[0][0]
        # Parcourir les sous-parties pour trouver le HTML
        html_found = False
        for part in msg.walk():
            if part.get_content_type() == "text/html":
                html = part.get_payload(decode=True).decode("utf-8")
                assert "Marie Leroy" in html
                assert "Amsterdam" in html
                assert "01/09/2026" in html
                html_found = True
        assert html_found, "Aucune partie HTML trouvee dans le message"

    @patch("app.services.email_service.smtplib.SMTP")
    @patch("app.services.email_service.settings", _mock_settings())
    def test_qr_code_attached_with_content_id(self, mock_smtp_cls):
        """Le QR code est attache en inline avec Content-ID <qrcode>."""
        from app.services.email_service import send_qr_code_email

        mock_server = MagicMock()
        mock_smtp_cls.return_value.__enter__ = MagicMock(return_value=mock_server)
        mock_smtp_cls.return_value.__exit__ = MagicMock(return_value=False)

        send_qr_code_email(
            to_email="parent@example.com",
            student_name="Test",
            trip_destination="Rome",
            trip_date=date(2026, 5, 1),
            qr_image_bytes=_FAKE_QR_BYTES,
        )

        msg = mock_server.send_message.call_args[0][0]
        # Chercher la piece jointe image
        image_found = False
        for part in msg.walk():
            if part.get_content_type() == "image/png":
                assert part["Content-ID"] == "<qrcode>"
                image_found = True
        assert image_found, "Aucune image PNG trouvee dans le message"

    @patch("app.services.email_service.smtplib.SMTP")
    @patch("app.services.email_service.settings", _mock_settings(SMTP_USE_TLS=True))
    def test_smtp_with_tls(self, mock_smtp_cls):
        """Quand SMTP_USE_TLS=True, starttls() est appele."""
        from app.services.email_service import send_qr_code_email

        mock_server = MagicMock()
        mock_smtp_cls.return_value.__enter__ = MagicMock(return_value=mock_server)
        mock_smtp_cls.return_value.__exit__ = MagicMock(return_value=False)

        send_qr_code_email(
            to_email="parent@example.com",
            student_name="Test",
            trip_destination="Rome",
            trip_date=date(2026, 5, 1),
            qr_image_bytes=_FAKE_QR_BYTES,
        )

        mock_server.starttls.assert_called_once()
        mock_server.login.assert_called_once()
        mock_server.send_message.assert_called_once()

    @patch("app.services.email_service.smtplib.SMTP")
    @patch("app.services.email_service.settings", _mock_settings(SMTP_USE_TLS=False, SMTP_USERNAME=""))
    def test_smtp_without_tls_and_no_auth(self, mock_smtp_cls):
        """Quand SMTP_USE_TLS=False et pas d'username, ni starttls ni login."""
        from app.services.email_service import send_qr_code_email

        mock_server = MagicMock()
        mock_smtp_cls.return_value.__enter__ = MagicMock(return_value=mock_server)
        mock_smtp_cls.return_value.__exit__ = MagicMock(return_value=False)

        send_qr_code_email(
            to_email="parent@example.com",
            student_name="Test",
            trip_destination="Rome",
            trip_date=date(2026, 5, 1),
            qr_image_bytes=_FAKE_QR_BYTES,
        )

        mock_server.starttls.assert_not_called()
        mock_server.login.assert_not_called()
        mock_server.send_message.assert_called_once()

    @patch("app.services.email_service.smtplib.SMTP")
    @patch("app.services.email_service.settings", _mock_settings())
    def test_from_and_to_headers(self, mock_smtp_cls):
        """Les headers From et To sont correctement definis."""
        from app.services.email_service import send_qr_code_email

        mock_server = MagicMock()
        mock_smtp_cls.return_value.__enter__ = MagicMock(return_value=mock_server)
        mock_smtp_cls.return_value.__exit__ = MagicMock(return_value=False)

        send_qr_code_email(
            to_email="parent@test.be",
            student_name="Test",
            trip_destination="Paris",
            trip_date=date(2026, 1, 1),
            qr_image_bytes=_FAKE_QR_BYTES,
        )

        msg = mock_server.send_message.call_args[0][0]
        assert msg["From"] == "noreply@schooltrack.be"
        assert msg["To"] == "parent@test.be"
