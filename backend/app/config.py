"""
Configuration centrale de l'application via variables d'environnement.
Charger depuis un fichier .env en développement.
"""

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    # Base de données
    DATABASE_URL: str = "postgresql://schooltrack:schooltrack_dev@localhost:5432/schooltrack"

    # JWT
    SECRET_KEY: str = "change-me-in-production"
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 30

    # SMTP — envoi des QR codes par email (US 1.6)
    SMTP_HOST: str = "localhost"
    SMTP_PORT: int = 587
    SMTP_USERNAME: str = ""
    SMTP_PASSWORD: str = ""
    SMTP_FROM: str = "schooltrack@school.be"
    SMTP_USE_TLS: bool = True

    # Environnement
    ENV: str = "development"

    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")


settings = Settings()
