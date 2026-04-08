"""
Tests unitaires pour la configuration (app/config.py).
Verifie que les valeurs par defaut sont correctes.
"""


class TestSettingsDefaults:
    """Verifie les valeurs par defaut de Settings sans fichier .env."""

    def test_database_url_default(self):
        """DATABASE_URL pointe vers localhost par defaut."""
        from app.config import Settings
        s = Settings()
        assert "localhost" in s.DATABASE_URL
        assert "schooltrack" in s.DATABASE_URL

    def test_smtp_port_default(self):
        """SMTP_PORT par defaut est 587 (STARTTLS standard)."""
        from app.config import Settings
        s = Settings()
        assert s.SMTP_PORT == 587

    def test_env_default(self):
        """ENV par defaut est 'development'."""
        from app.config import Settings
        s = Settings()
        assert s.ENV == "development"

    def test_access_token_expire_default(self):
        """ACCESS_TOKEN_EXPIRE_MINUTES par defaut est 30."""
        from app.config import Settings
        s = Settings()
        assert s.ACCESS_TOKEN_EXPIRE_MINUTES == 30

    def test_smtp_use_tls_default(self):
        """SMTP_USE_TLS par defaut est True."""
        from app.config import Settings
        s = Settings()
        assert s.SMTP_USE_TLS is True

    def test_algorithm_default(self):
        """ALGORITHM par defaut est HS256."""
        from app.config import Settings
        s = Settings()
        assert s.ALGORITHM == "HS256"
