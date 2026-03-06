"""
Tests d'integration API pour l'authentification (US 6.1).
Testent les URLs, codes HTTP, validation et format des reponses.
"""

import uuid
from datetime import datetime, timedelta, timezone
from unittest.mock import MagicMock, patch

import pyotp
import pytest

from app.models.user import User
from app.services.auth_service import (
    AccountLockedError,
    AuthError,
    TwoFactorRequiredError,
    create_access_token,
    create_refresh_token,
    hash_password,
)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def make_user(**kwargs) -> User:
    user = User()
    user.id = kwargs.get("id", uuid.uuid4())
    user.email = kwargs.get("email", "test@school.be")
    user.password_hash = kwargs.get("password_hash", hash_password("Test1234!"))
    user.first_name = kwargs.get("first_name", "Test")
    user.last_name = kwargs.get("last_name", "User")
    user.role = kwargs.get("role", "TEACHER")
    user.totp_secret = kwargs.get("totp_secret", None)
    user.is_2fa_enabled = kwargs.get("is_2fa_enabled", False)
    user.failed_attempts = kwargs.get("failed_attempts", 0)
    user.locked_until = kwargs.get("locked_until", None)
    user.last_login = kwargs.get("last_login", None)
    return user


def auth_header(user: User) -> dict:
    token = create_access_token(user)
    return {"Authorization": f"Bearer {token}"}


# ============================================================
# POST /api/v1/auth/login
# ============================================================

class TestLogin:
    def test_login_success(self, client):
        user = make_user()
        with patch("app.routers.auth.authenticate_user", return_value=user):
            resp = client.post("/api/v1/auth/login", json={
                "email": "test@school.be",
                "password": "Test1234!",
            })
        assert resp.status_code == 200
        data = resp.json()
        assert "access_token" in data
        assert "refresh_token" in data
        assert data["token_type"] == "bearer"
        assert data["user"]["email"] == "test@school.be"
        assert data["user"]["role"] == "TEACHER"

    def test_login_wrong_credentials(self, client):
        with patch("app.routers.auth.authenticate_user", side_effect=AuthError("Identifiants invalides")):
            resp = client.post("/api/v1/auth/login", json={
                "email": "test@school.be",
                "password": "Wrong1234!",
            })
        assert resp.status_code == 401

    def test_login_account_locked(self, client):
        with patch("app.routers.auth.authenticate_user", side_effect=AccountLockedError("Compte verrouille")):
            resp = client.post("/api/v1/auth/login", json={
                "email": "test@school.be",
                "password": "Test1234!",
            })
        assert resp.status_code == 423

    def test_login_2fa_required(self, client):
        with patch("app.routers.auth.authenticate_user", side_effect=TwoFactorRequiredError("Code 2FA requis")):
            resp = client.post("/api/v1/auth/login", json={
                "email": "test@school.be",
                "password": "Test1234!",
            })
        assert resp.status_code == 400
        assert "2FA" in resp.json()["detail"]

    def test_login_invalid_email_format(self, client):
        resp = client.post("/api/v1/auth/login", json={
            "email": "not-an-email",
            "password": "Test1234!",
        })
        assert resp.status_code == 422


# ============================================================
# POST /api/v1/auth/register
# ============================================================

class TestRegister:
    def test_register_success(self, client):
        user = make_user(email="new@school.be")
        # Configurer le mock_db pour que query().filter().first() retourne None (pas de doublon)
        from app.database import get_db
        from app.main import app

        mock_db = MagicMock()
        mock_db.query.return_value.filter.return_value.first.return_value = None
        app.dependency_overrides[get_db] = lambda: mock_db

        with patch("app.routers.auth.register_user", return_value=user):
            resp = client.post("/api/v1/auth/register", json={
                "email": "new@school.be",
                "password": "Test1234!",
                "first_name": "New",
                "last_name": "User",
                "role": "TEACHER",
            })
        assert resp.status_code == 201
        assert resp.json()["email"] == "new@school.be"

    def test_register_weak_password_no_uppercase(self, client):
        resp = client.post("/api/v1/auth/register", json={
            "email": "new@school.be",
            "password": "test1234!",
            "role": "TEACHER",
        })
        assert resp.status_code == 422
        assert "majuscule" in resp.json()["detail"][0]["msg"]

    def test_register_weak_password_no_digit(self, client):
        resp = client.post("/api/v1/auth/register", json={
            "email": "new@school.be",
            "password": "Testtest!",
            "role": "TEACHER",
        })
        assert resp.status_code == 422
        assert "chiffre" in resp.json()["detail"][0]["msg"]

    def test_register_weak_password_no_special(self, client):
        resp = client.post("/api/v1/auth/register", json={
            "email": "new@school.be",
            "password": "Testtest1",
            "role": "TEACHER",
        })
        assert resp.status_code == 422
        assert "special" in resp.json()["detail"][0]["msg"]

    def test_register_weak_password_too_short(self, client):
        resp = client.post("/api/v1/auth/register", json={
            "email": "new@school.be",
            "password": "Te1!",
            "role": "TEACHER",
        })
        assert resp.status_code == 422
        assert "8 caracteres" in resp.json()["detail"][0]["msg"]

    def test_register_invalid_role(self, client):
        resp = client.post("/api/v1/auth/register", json={
            "email": "new@school.be",
            "password": "Test1234!",
            "role": "SUPERADMIN",
        })
        assert resp.status_code == 422

    def test_register_duplicate_email(self, client):
        existing = make_user()
        # Le mock db retourne un user existant pour filter().first()
        with patch("app.routers.auth.register_user") as mock_reg:
            mock_reg.return_value = existing
            resp = client.post("/api/v1/auth/register", json={
                "email": "test@school.be",
                "password": "Test1234!",
                "role": "TEACHER",
            })
        # Le mock_db du conftest retourne un MagicMock (truthy) pour .query().filter().first()
        assert resp.status_code == 409


# ============================================================
# POST /api/v1/auth/refresh
# ============================================================

class TestRefresh:
    def test_refresh_success(self, client):
        user = make_user()
        with patch("app.routers.auth.refresh_access_token", return_value=user):
            resp = client.post("/api/v1/auth/refresh", json={
                "refresh_token": create_refresh_token(user),
            })
        assert resp.status_code == 200
        assert "access_token" in resp.json()

    def test_refresh_invalid_token(self, client):
        with patch("app.routers.auth.refresh_access_token", side_effect=AuthError("invalide")):
            resp = client.post("/api/v1/auth/refresh", json={
                "refresh_token": "invalid.token.here",
            })
        assert resp.status_code == 401


# ============================================================
# GET /api/v1/auth/me
# ============================================================

class TestMe:
    def test_me_authenticated(self, client):
        user = make_user()
        from app.dependencies import get_current_user
        from app.main import app
        app.dependency_overrides[get_current_user] = lambda: user
        resp = client.get("/api/v1/auth/me")
        app.dependency_overrides.pop(get_current_user, None)
        assert resp.status_code == 200
        assert resp.json()["email"] == "test@school.be"

    def test_me_no_token(self, client):
        # HTTPBearer renvoie 403 si pas de header Authorization
        from app.dependencies import get_current_user
        from app.main import app
        app.dependency_overrides.pop(get_current_user, None)
        resp = client.get("/api/v1/auth/me")
        assert resp.status_code == 403


# ============================================================
# POST /api/v1/auth/enable-2fa + verify-2fa
# ============================================================

class TestTwoFactor:
    def _override_user(self, client, user):
        from app.dependencies import get_current_user
        from app.main import app
        app.dependency_overrides[get_current_user] = lambda: user
        return app

    def _cleanup(self):
        from app.dependencies import get_current_user
        from app.main import app
        app.dependency_overrides.pop(get_current_user, None)

    def test_enable_2fa_success(self, client):
        user = make_user()
        app = self._override_user(client, user)
        with patch("app.routers.auth.enable_2fa", return_value=("SECRET", "otpauth://totp/test")):
            resp = client.post("/api/v1/auth/enable-2fa")
        self._cleanup()
        assert resp.status_code == 200
        assert resp.json()["secret"] == "SECRET"
        assert "otpauth" in resp.json()["provisioning_uri"]

    def test_enable_2fa_already_enabled(self, client):
        user = make_user(is_2fa_enabled=True)
        self._override_user(client, user)
        resp = client.post("/api/v1/auth/enable-2fa")
        self._cleanup()
        assert resp.status_code == 400
        assert "deja active" in resp.json()["detail"]

    def test_verify_2fa_success(self, client):
        user = make_user()
        self._override_user(client, user)
        with patch("app.routers.auth.verify_and_activate_2fa", return_value=True):
            resp = client.post("/api/v1/auth/verify-2fa", json={"totp_code": "123456"})
        self._cleanup()
        assert resp.status_code == 200

    def test_verify_2fa_wrong_code(self, client):
        user = make_user()
        self._override_user(client, user)
        with patch("app.routers.auth.verify_and_activate_2fa", return_value=False):
            resp = client.post("/api/v1/auth/verify-2fa", json={"totp_code": "000000"})
        self._cleanup()
        assert resp.status_code == 400

    def test_disable_2fa_success(self, client):
        user = make_user(is_2fa_enabled=True)
        self._override_user(client, user)
        with patch("app.routers.auth.disable_2fa"):
            resp = client.post("/api/v1/auth/disable-2fa")
        self._cleanup()
        assert resp.status_code == 200

    def test_disable_2fa_not_enabled(self, client):
        user = make_user(is_2fa_enabled=False)
        self._override_user(client, user)
        resp = client.post("/api/v1/auth/disable-2fa")
        self._cleanup()
        assert resp.status_code == 400


# ============================================================
# POST /api/v1/auth/change-password
# ============================================================

class TestChangePassword:
    def test_change_password_success(self, client):
        user = make_user()
        from app.dependencies import get_current_user
        from app.main import app
        app.dependency_overrides[get_current_user] = lambda: user
        with patch("app.routers.auth.change_password"):
            resp = client.post("/api/v1/auth/change-password", json={
                "current_password": "Test1234!",
                "new_password": "NewPass1!",
            })
        app.dependency_overrides.pop(get_current_user, None)
        assert resp.status_code == 200

    def test_change_password_wrong_current(self, client):
        user = make_user()
        from app.dependencies import get_current_user
        from app.main import app
        app.dependency_overrides[get_current_user] = lambda: user
        with patch("app.routers.auth.change_password", side_effect=AuthError("Mot de passe actuel incorrect")):
            resp = client.post("/api/v1/auth/change-password", json={
                "current_password": "Wrong1234!",
                "new_password": "NewPass1!",
            })
        app.dependency_overrides.pop(get_current_user, None)
        assert resp.status_code == 400

    def test_change_password_weak_new(self, client):
        user = make_user()
        from app.dependencies import get_current_user
        from app.main import app
        app.dependency_overrides[get_current_user] = lambda: user
        resp = client.post("/api/v1/auth/change-password", json={
            "current_password": "Test1234!",
            "new_password": "weak",
        })
        app.dependency_overrides.pop(get_current_user, None)
        assert resp.status_code == 422
