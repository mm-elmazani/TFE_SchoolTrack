"""
Configuration centrale de l'application via variables d'environnement.
Charger depuis un fichier .env en développement.
"""

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    # Base de données
    DATABASE_URL: str = "postgresql://schooltrack:schooltrack_dev@localhost:5432/schooltrack"

    # Chiffrement AES-256 des donnees sensibles
    ENCRYPTION_KEY: str = "dev-only-change-in-production-32chars!"

    # JWT
    SECRET_KEY: str = "change-me-in-production"
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 30
    REFRESH_TOKEN_EXPIRE_MINUTES: int = 1440  # 24h (defaut)
    EXTENDED_REFRESH_TOKEN_EXPIRE_MINUTES: int = 10080  # 7 jours (case "rester connecte")
    PASSWORD_RESET_TOKEN_EXPIRE_MINUTES: int = 10

    # SMTP — envoi des QR codes par email
    SMTP_HOST: str = "localhost"
    SMTP_PORT: int = 587
    SMTP_USERNAME: str = ""
    SMTP_PASSWORD: str = ""
    SMTP_FROM: str = "schooltrack@school.be"
    SMTP_USE_TLS: bool = True

    # Fichiers media (photos élèves)
    MEDIA_DIR: str = "/app/media"

    # Environnement
    ENV: str = "development"

    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")


settings = Settings()
