"""
Point d'entrée principal de l'API SchoolTrack.
Démarrage : uvicorn app.main:app --reload
"""

import logging
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import Depends, FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from sqlalchemy import text
from sqlalchemy.orm import Session

import app.models  # noqa: F401 — enregistre tous les modèles SQLAlchemy dans les métadonnées
from app.config import settings
from app.database import get_db
from app.routers import alerts, audit, auth, checkpoints, classes, dashboard, schools, students, sync, tokens, trips, users
from app.routers.checkpoints import checkpoints_router
from app.scheduler import start_scheduler, stop_scheduler

logger = logging.getLogger(__name__)

# Création des dossiers media au démarrage (idempotent)
Path(settings.MEDIA_DIR).mkdir(parents=True, exist_ok=True)
Path(settings.MEDIA_DIR, "students").mkdir(exist_ok=True)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Cycle de vie de l'application : démarre et arrête le scheduler APScheduler."""
    start_scheduler()
    yield
    stop_scheduler()


app = FastAPI(
    title="SchoolTrack API",
    description="API de gestion des présences pour sorties scolaires (offline-first)",
    version="0.1.0",
    docs_url="/api/docs",
    redoc_url="/api/redoc",
    openapi_url="/api/openapi.json",
    lifespan=lifespan,
)

# CORS — autorise localhost + réseau local 192.168.x.x en développement (à restreindre en production).
# allow_origin_regex est nécessaire pour les requêtes preflight POST avec Content-Type JSON.
app.add_middleware(
    CORSMiddleware,
    allow_origins=[],
    allow_origin_regex=r"https?://(localhost|127\.0\.0\.1|192\.168\.\d+\.\d+)(:\d+)?|https://dashboard\.schooltrack\.yourschool\.be",
    allow_credentials=False,
    allow_methods=["GET", "POST", "PUT", "DELETE", "OPTIONS", "PATCH"],
    allow_headers=["Content-Type", "Authorization", "Accept"],
)


app.include_router(schools.router)
app.include_router(auth.router)
app.include_router(users.router)
app.include_router(students.router)
app.include_router(trips.router)
app.include_router(checkpoints.router)
app.include_router(checkpoints_router)
app.include_router(classes.router)
app.include_router(tokens.router)
app.include_router(sync.router)
app.include_router(audit.router)
app.include_router(alerts.router)
app.include_router(dashboard.router)


@app.exception_handler(Exception)
async def unhandled_exception_handler(request: Request, exc: Exception) -> JSONResponse:
    """
    Intercepte toutes les exceptions non gérées pour garantir que la réponse 500
    passe bien par CORSMiddleware (qui injecte les headers CORS).
    Sans ce handler, ServerErrorMiddleware renvoie une réponse brute sans headers CORS,
    ce qui provoque une erreur "Failed to fetch" côté navigateur.
    """
    logger.error("Exception non gérée : %s", exc, exc_info=True)
    return JSONResponse(
        status_code=500,
        content={"detail": "Une erreur interne est survenue."},
    )


@app.get("/api/health", tags=["Santé"])
def health_check(db: Session = Depends(get_db)):
    """Vérifie que l'API et la connexion PostgreSQL sont opérationnelles."""
    try:
        db.execute(text("SELECT 1"))
        db_status = "connected"
    except Exception:
        return JSONResponse(
            status_code=503,
            content={"status": "degraded", "db": "disconnected", "version": "1.0.0"},
        )
    return {"status": "ok", "db": db_status, "version": "1.0.0"}
