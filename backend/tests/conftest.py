"""
Configuration partagée pour tous les tests.
Override la dépendance get_db pour éviter toute connexion réelle à PostgreSQL.
"""

import pytest
from fastapi.testclient import TestClient
from unittest.mock import MagicMock

from app.database import get_db
from app.main import app


@pytest.fixture
def client():
    """Client HTTP de test avec la BDD mockée."""
    mock_db = MagicMock()
    app.dependency_overrides[get_db] = lambda: mock_db
    with TestClient(app) as c:
        yield c
    app.dependency_overrides.clear()
