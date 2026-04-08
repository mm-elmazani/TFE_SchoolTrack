"""
Tests pour le point d'entree principal de l'API (app/main.py).
Couvre le health check, le handler d'exceptions, et l'enregistrement des routers.
"""

from unittest.mock import MagicMock, patch

import pytest
from fastapi.testclient import TestClient

from app.database import get_db
from app.dependencies import get_current_user
from app.main import app
from app.models.user import User


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

def _make_user():
    import uuid
    user = User()
    user.id = uuid.uuid4()
    user.school_id = uuid.uuid4()
    user.email = "test@schooltrack.be"
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


# ============================================================
# Health check
# ============================================================

class TestHealthCheck:
    """Tests pour GET /api/health."""

    def test_health_ok(self):
        """Health check retourne 200 + status ok quand la DB est connectee."""
        mock_db = MagicMock()
        app.dependency_overrides[get_db] = lambda: mock_db
        app.dependency_overrides[get_current_user] = lambda: _make_user()

        with TestClient(app) as client:
            response = client.get("/api/health")

        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "ok"
        assert data["db"] == "connected"
        assert "version" in data
        app.dependency_overrides.clear()

    def test_health_db_down(self):
        """Health check retourne 503 quand la DB est deconnectee."""
        mock_db = MagicMock()
        mock_db.execute.side_effect = Exception("Connection refused")
        app.dependency_overrides[get_db] = lambda: mock_db
        app.dependency_overrides[get_current_user] = lambda: _make_user()

        with TestClient(app) as client:
            response = client.get("/api/health")

        assert response.status_code == 503
        data = response.json()
        assert data["status"] == "degraded"
        assert data["db"] == "disconnected"
        app.dependency_overrides.clear()


# ============================================================
# Exception handler
# ============================================================

class TestExceptionHandler:
    """Tests pour le handler d'exceptions non gerees."""

    def test_unhandled_exception_returns_500(self):
        """Une exception non geree retourne 500 JSON au lieu de crasher."""
        mock_db = MagicMock()
        app.dependency_overrides[get_db] = lambda: mock_db
        app.dependency_overrides[get_current_user] = lambda: _make_user()

        # Creer une route temporaire qui leve une exception
        @app.get("/api/test-crash-500")
        def crash_endpoint():
            raise RuntimeError("Bug inattendu")

        with TestClient(app, raise_server_exceptions=False) as client:
            response = client.get("/api/test-crash-500")

        assert response.status_code == 500
        assert "erreur interne" in response.json()["detail"]
        app.dependency_overrides.clear()


# ============================================================
# Routers enregistres
# ============================================================

class TestRouterRegistration:
    """Verifie que tous les routers sont bien enregistres."""

    def test_all_major_routes_exist(self):
        """Les prefixes principaux sont enregistres dans l'app."""
        route_paths = [route.path for route in app.routes]

        expected_prefixes = [
            "/api/v1/schools",
            "/api/v1/auth",
            "/api/v1/users",
            "/api/v1/students",
            "/api/v1/trips",
            "/api/v1/classes",
            "/api/v1/tokens",
            "/api/v1/audit",
            "/api/v1/alerts",
            "/api/v1/dashboard",
            "/api/health",
        ]

        for prefix in expected_prefixes:
            matches = [p for p in route_paths if p.startswith(prefix)]
            assert len(matches) > 0, f"Aucune route trouvee pour le prefix {prefix}"

    def test_sync_routes_exist(self):
        """Les routes sync (sans /v1/) sont enregistrees."""
        route_paths = [route.path for route in app.routes]
        sync_routes = [p for p in route_paths if "/sync" in p]
        assert len(sync_routes) > 0, "Aucune route sync trouvee"

    def test_docs_url_configured(self):
        """La documentation Swagger est accessible sur /api/docs."""
        assert app.docs_url == "/api/docs"

    def test_openapi_url_configured(self):
        """Le schema OpenAPI est accessible sur /api/openapi.json."""
        assert app.openapi_url == "/api/openapi.json"
