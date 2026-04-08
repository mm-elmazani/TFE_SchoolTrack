"""
Tests unitaires pour les dependances FastAPI (app/dependencies.py).
Couvre get_current_user, require_role, get_client_ip, log_audit.
"""

import uuid
from unittest.mock import MagicMock, patch

import pytest
from fastapi import HTTPException

from app.dependencies import get_client_ip, get_current_user, log_audit, require_role
from app.models.user import User


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _make_user(role="DIRECTION"):
    user = User()
    user.id = uuid.uuid4()
    user.school_id = uuid.uuid4()
    user.email = "test@schooltrack.be"
    user.password_hash = "$2b$12$fake"
    user.first_name = "Test"
    user.last_name = "Admin"
    user.role = role
    user.totp_secret = None
    user.is_2fa_enabled = False
    user.failed_attempts = 0
    user.locked_until = None
    user.last_login = None
    return user


# ============================================================
# get_current_user
# ============================================================

class TestGetCurrentUser:
    """Tests pour l'extraction de l'utilisateur depuis le JWT."""

    @patch("app.dependencies.decode_token")
    def test_valid_token_returns_user(self, mock_decode):
        """Un JWT valide avec type=access retourne l'utilisateur."""
        user = _make_user()
        mock_decode.return_value = {"type": "access", "sub": str(user.id)}

        mock_db = MagicMock()
        mock_db.query.return_value.filter.return_value.first.return_value = user

        mock_credentials = MagicMock()
        mock_credentials.credentials = "valid.jwt.token"

        result = get_current_user(credentials=mock_credentials, db=mock_db)
        assert result.id == user.id

    @patch("app.dependencies.decode_token")
    def test_invalid_token_raises_401(self, mock_decode):
        """Un JWT invalide leve HTTP 401."""
        from jose import JWTError
        mock_decode.side_effect = JWTError("invalid")

        mock_credentials = MagicMock()
        mock_credentials.credentials = "invalid.jwt"

        with pytest.raises(HTTPException) as exc_info:
            get_current_user(credentials=mock_credentials, db=MagicMock())
        assert exc_info.value.status_code == 401

    @patch("app.dependencies.decode_token")
    def test_non_access_token_raises_401(self, mock_decode):
        """Un token refresh (type != access) leve HTTP 401."""
        mock_decode.return_value = {"type": "refresh", "sub": str(uuid.uuid4())}

        mock_credentials = MagicMock()
        mock_credentials.credentials = "refresh.jwt.token"

        with pytest.raises(HTTPException) as exc_info:
            get_current_user(credentials=mock_credentials, db=MagicMock())
        assert exc_info.value.status_code == 401
        assert "type attendu: access" in exc_info.value.detail

    @patch("app.dependencies.decode_token")
    def test_user_not_found_raises_401(self, mock_decode):
        """Si l'utilisateur n'existe pas en DB → 401."""
        mock_decode.return_value = {"type": "access", "sub": str(uuid.uuid4())}

        mock_db = MagicMock()
        mock_db.query.return_value.filter.return_value.first.return_value = None

        mock_credentials = MagicMock()
        mock_credentials.credentials = "valid.jwt.token"

        with pytest.raises(HTTPException) as exc_info:
            get_current_user(credentials=mock_credentials, db=mock_db)
        assert exc_info.value.status_code == 401
        assert "introuvable" in exc_info.value.detail


# ============================================================
# require_role
# ============================================================

class TestRequireRole:
    """Tests pour la fabrique de dependance role."""

    def test_allowed_role_passes(self):
        """Un utilisateur avec un role autorise passe sans erreur."""
        checker = require_role("DIRECTION", "ADMIN_TECH")
        user = _make_user("DIRECTION")
        result = checker(current_user=user)
        assert result.role == "DIRECTION"

    def test_forbidden_role_raises_403(self):
        """Un utilisateur avec un role interdit leve HTTP 403."""
        checker = require_role("ADMIN_TECH")
        user = _make_user("TEACHER")
        with pytest.raises(HTTPException) as exc_info:
            checker(current_user=user)
        assert exc_info.value.status_code == 403

    def test_multiple_roles_accepted(self):
        """Plusieurs roles sont acceptes dans la meme dependance."""
        checker = require_role("DIRECTION", "TEACHER", "ADMIN_TECH")
        for role in ("DIRECTION", "TEACHER", "ADMIN_TECH"):
            user = _make_user(role)
            result = checker(current_user=user)
            assert result.role == role


# ============================================================
# get_client_ip
# ============================================================

class TestGetClientIp:
    """Tests pour l'extraction de l'IP client."""

    def test_from_x_forwarded_for(self):
        """Extrait l'IP depuis le header X-Forwarded-For (premier element)."""
        request = MagicMock()
        request.headers = {"x-forwarded-for": "203.0.113.50, 70.41.3.18"}
        result = get_client_ip(request)
        assert result == "203.0.113.50"

    def test_from_request_client(self):
        """Fallback sur request.client.host si pas de header proxy."""
        request = MagicMock()
        request.headers = {}
        request.client.host = "127.0.0.1"
        result = get_client_ip(request)
        assert result == "127.0.0.1"

    def test_no_client_returns_none(self):
        """Retourne None si request.client est None et pas de proxy."""
        request = MagicMock()
        request.headers = {}
        request.client = None
        result = get_client_ip(request)
        assert result is None


# ============================================================
# log_audit
# ============================================================

class TestLogAudit:
    """Tests pour l'insertion d'un log d'audit."""

    def test_inserts_with_correct_params(self):
        """Verifie que log_audit execute un INSERT avec les bons parametres."""
        mock_db = MagicMock()
        user_id = uuid.uuid4()

        log_audit(
            mock_db,
            user_id=user_id,
            action="LOGIN",
            resource_type="user",
            resource_id=user_id,
            ip_address="192.168.1.1",
            user_agent="TestAgent/1.0",
            details={"method": "password"},
        )

        mock_db.execute.assert_called_once()
        mock_db.commit.assert_called_once()
        # Verifie que les parametres SQL contiennent l'action
        call_args = mock_db.execute.call_args[0]
        params = call_args[1]
        assert params["action"] == "LOGIN"
        assert params["ip"] == "192.168.1.1"

    def test_inserts_with_none_optionals(self):
        """Fonctionne avec les parametres optionnels a None."""
        mock_db = MagicMock()

        log_audit(
            mock_db,
            user_id=None,
            action="SYSTEM_EVENT",
        )

        mock_db.execute.assert_called_once()
        params = mock_db.execute.call_args[0][1]
        assert params["uid"] is None
        assert params["rtype"] is None
        assert params["details"] is None
