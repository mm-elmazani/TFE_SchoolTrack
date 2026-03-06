"""
Tests unitaires du service d'authentification (US 6.1).
Couvre : hachage, JWT, verrouillage de compte, TOTP 2FA.
"""

import uuid
from datetime import datetime, timedelta, timezone
from unittest.mock import MagicMock, patch

import pyotp
import pytest
from jose import jwt

from app.config import settings
from app.models.user import User
from app.services.auth_service import (
    AccountLockedError,
    AuthError,
    TwoFactorRequiredError,
    authenticate_user,
    change_password,
    create_access_token,
    create_refresh_token,
    decode_token,
    enable_2fa,
    hash_password,
    refresh_access_token,
    register_user,
    verify_and_activate_2fa,
    verify_password,
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


def mock_db_with_user(user):
    db = MagicMock()
    db.query.return_value.filter.return_value.first.return_value = user
    return db


# ---------------------------------------------------------------------------
# Hachage bcrypt
# ---------------------------------------------------------------------------

class TestPasswordHashing:
    def test_hash_password_returns_bcrypt_hash(self):
        h = hash_password("Test1234!")
        assert h.startswith("$2b$12$")

    def test_verify_password_correct(self):
        h = hash_password("Test1234!")
        assert verify_password("Test1234!", h) is True

    def test_verify_password_wrong(self):
        h = hash_password("Test1234!")
        assert verify_password("Wrong1234!", h) is False

    def test_hash_is_unique_each_time(self):
        h1 = hash_password("Test1234!")
        h2 = hash_password("Test1234!")
        assert h1 != h2  # bcrypt salt different


# ---------------------------------------------------------------------------
# JWT access / refresh
# ---------------------------------------------------------------------------

class TestJWT:
    def test_create_access_token_valid(self):
        user = make_user()
        token = create_access_token(user)
        payload = jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])
        assert payload["sub"] == str(user.id)
        assert payload["type"] == "access"
        assert payload["role"] == "TEACHER"

    def test_create_refresh_token_valid(self):
        user = make_user()
        token = create_refresh_token(user)
        payload = jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])
        assert payload["sub"] == str(user.id)
        assert payload["type"] == "refresh"
        assert "role" not in payload  # le refresh ne contient pas le role

    def test_decode_token_success(self):
        user = make_user()
        token = create_access_token(user)
        payload = decode_token(token)
        assert payload["email"] == user.email

    def test_decode_token_expired(self):
        from jose import jwt as jose_jwt

        payload = {
            "sub": str(uuid.uuid4()),
            "type": "access",
            "exp": datetime.now(timezone.utc) - timedelta(hours=1),
        }
        token = jose_jwt.encode(payload, settings.SECRET_KEY, algorithm=settings.ALGORITHM)
        with pytest.raises(Exception):
            decode_token(token)

    def test_decode_token_invalid_signature(self):
        user = make_user()
        token = jwt.encode(
            {"sub": str(user.id), "type": "access", "exp": datetime.now(timezone.utc) + timedelta(hours=1)},
            "wrong-secret",
            algorithm=settings.ALGORITHM,
        )
        with pytest.raises(Exception):
            decode_token(token)


# ---------------------------------------------------------------------------
# Authentification (login)
# ---------------------------------------------------------------------------

class TestAuthentication:
    def test_login_success(self):
        user = make_user()
        db = mock_db_with_user(user)
        result = authenticate_user(db, "test@school.be", "Test1234!")
        assert result.email == "test@school.be"
        assert result.failed_attempts == 0

    def test_login_wrong_password_increments_failed_attempts(self):
        user = make_user(failed_attempts=0)
        db = mock_db_with_user(user)
        with pytest.raises(AuthError, match="Identifiants invalides"):
            authenticate_user(db, "test@school.be", "WrongPass1!")
        assert user.failed_attempts == 1

    def test_login_user_not_found(self):
        db = MagicMock()
        db.query.return_value.filter.return_value.first.return_value = None
        with pytest.raises(AuthError, match="Identifiants invalides"):
            authenticate_user(db, "unknown@school.be", "Test1234!")

    def test_login_locks_after_5_attempts(self):
        user = make_user(failed_attempts=4)
        db = mock_db_with_user(user)
        with pytest.raises(AuthError):
            authenticate_user(db, "test@school.be", "WrongPass1!")
        assert user.failed_attempts == 5
        assert user.locked_until is not None

    def test_login_blocked_when_locked(self):
        user = make_user(
            locked_until=datetime.utcnow() + timedelta(minutes=10),
        )
        db = mock_db_with_user(user)
        with pytest.raises(AccountLockedError, match="Compte verrouille"):
            authenticate_user(db, "test@school.be", "Test1234!")

    def test_login_success_resets_failed_attempts(self):
        user = make_user(failed_attempts=3)
        db = mock_db_with_user(user)
        authenticate_user(db, "test@school.be", "Test1234!")
        assert user.failed_attempts == 0
        assert user.locked_until is None

    def test_login_success_updates_last_login(self):
        user = make_user()
        db = mock_db_with_user(user)
        authenticate_user(db, "test@school.be", "Test1234!")
        assert user.last_login is not None

    def test_login_with_2fa_required(self):
        secret = pyotp.random_base32()
        user = make_user(is_2fa_enabled=True, totp_secret=secret)
        db = mock_db_with_user(user)
        with pytest.raises(TwoFactorRequiredError):
            authenticate_user(db, "test@school.be", "Test1234!")

    def test_login_with_2fa_valid_code(self):
        secret = pyotp.random_base32()
        totp = pyotp.TOTP(secret)
        user = make_user(is_2fa_enabled=True, totp_secret=secret)
        db = mock_db_with_user(user)
        result = authenticate_user(db, "test@school.be", "Test1234!", totp.now())
        assert result.email == "test@school.be"

    def test_login_with_2fa_invalid_code(self):
        secret = pyotp.random_base32()
        user = make_user(is_2fa_enabled=True, totp_secret=secret)
        db = mock_db_with_user(user)
        with pytest.raises(AuthError, match="2FA invalide"):
            authenticate_user(db, "test@school.be", "Test1234!", "000000")


# ---------------------------------------------------------------------------
# Register
# ---------------------------------------------------------------------------

class TestRegister:
    def test_register_user_success(self):
        db = MagicMock()
        user = register_user(
            db=db,
            email="new@school.be",
            password_hash=hash_password("Test1234!"),
            first_name="New",
            last_name="User",
            role="TEACHER",
        )
        db.add.assert_called_once()
        db.commit.assert_called_once()
        db.refresh.assert_called_once()


# ---------------------------------------------------------------------------
# Refresh token
# ---------------------------------------------------------------------------

class TestRefreshToken:
    def test_refresh_success(self):
        user = make_user()
        db = mock_db_with_user(user)
        token = create_refresh_token(user)
        result = refresh_access_token(db, token)
        assert result.email == user.email

    def test_refresh_with_access_token_fails(self):
        user = make_user()
        db = mock_db_with_user(user)
        token = create_access_token(user)
        with pytest.raises(AuthError, match="type attendu: refresh"):
            refresh_access_token(db, token)

    def test_refresh_with_invalid_token_fails(self):
        db = MagicMock()
        with pytest.raises(AuthError, match="invalide ou expire"):
            refresh_access_token(db, "invalid.token.here")


# ---------------------------------------------------------------------------
# 2FA TOTP
# ---------------------------------------------------------------------------

class TestTOTP:
    def test_enable_2fa_generates_secret(self):
        user = make_user()
        db = MagicMock()
        secret, uri = enable_2fa(db, user)
        assert len(secret) > 0
        assert "otpauth://totp/" in uri
        assert "SchoolTrack" in uri

    def test_verify_and_activate_2fa_success(self):
        user = make_user()
        db = MagicMock()
        secret, _ = enable_2fa(db, user)
        totp = pyotp.TOTP(secret)
        result = verify_and_activate_2fa(db, user, totp.now())
        assert result is True
        assert user.is_2fa_enabled is True

    def test_verify_2fa_wrong_code(self):
        user = make_user()
        db = MagicMock()
        enable_2fa(db, user)
        result = verify_and_activate_2fa(db, user, "000000")
        assert result is False
        assert user.is_2fa_enabled is False

    def test_verify_2fa_without_enable_first(self):
        user = make_user(totp_secret=None)
        db = MagicMock()
        with pytest.raises(AuthError, match="non initialisee"):
            verify_and_activate_2fa(db, user, "123456")


# ---------------------------------------------------------------------------
# Changement de mot de passe
# ---------------------------------------------------------------------------

class TestChangePassword:
    def test_change_password_success(self):
        user = make_user()
        db = MagicMock()
        change_password(db, user, "Test1234!", hash_password("NewPass1!"))
        db.commit.assert_called_once()

    def test_change_password_wrong_current(self):
        user = make_user()
        db = MagicMock()
        with pytest.raises(AuthError, match="Mot de passe actuel incorrect"):
            change_password(db, user, "WrongPass!", hash_password("NewPass1!"))
