"""
Configuration partagée pour tous les tests.
Override la dépendance get_db pour éviter toute connexion réelle à PostgreSQL.
Injecte un utilisateur DIRECTION par défaut pour passer les guards d'auth (US 6.2).
"""

import uuid

import pytest
from fastapi.testclient import TestClient
from unittest.mock import MagicMock

from app.database import get_db
from app.dependencies import get_current_user
from app.main import app
from app.models.user import User


_DEFAULT_SCHOOL_ID = uuid.uuid4()


def _make_default_user() -> User:
    """Cree un utilisateur DIRECTION fictif pour les tests."""
    user = User()
    user.id = uuid.uuid4()
    user.school_id = _DEFAULT_SCHOOL_ID
    user.email = "test-admin@schooltrack.be"
    user.password_hash = "$2b$12$fake"
    user.first_name = "Test"
    user.last_name = "Admin"
    user.role = "DIRECTION"
    user.totp_secret = None
    user.is_2fa_enabled = False
    user.failed_attempts = 0
    user.locked_until = None
    user.last_login = None
    return user


@pytest.fixture
def client():
    """Client HTTP de test avec la BDD mockée et un utilisateur DIRECTION par défaut."""
    mock_db = MagicMock()
    app.dependency_overrides[get_db] = lambda: mock_db
    app.dependency_overrides[get_current_user] = lambda: _make_default_user()
    with TestClient(app) as c:
        yield c
    app.dependency_overrides.clear()
