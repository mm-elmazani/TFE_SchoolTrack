"""
Point d'entrée principal de l'API SchoolTrack.
Démarrage : uvicorn app.main:app --reload
"""

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

import app.models  # noqa: F401 — enregistre tous les modèles dans Base.metadata avant les routers
from app.routers import classes, students, sync, tokens, trips
from app.scheduler import start_scheduler, stop_scheduler

logger = logging.getLogger(__name__)


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

# CORS — autorise tous les ports localhost en développement (à restreindre en production).
# allow_origin_regex est nécessaire pour les requêtes preflight POST avec Content-Type JSON.
app.add_middleware(
    CORSMiddleware,
    allow_origins=[],
    allow_origin_regex=r"https?://(localhost|127\.0\.0\.1)(:\d+)?",
    allow_credentials=False,
    allow_methods=["GET", "POST", "PUT", "DELETE", "OPTIONS", "PATCH"],
    allow_headers=["Content-Type", "Authorization", "Accept"],
)


app.include_router(students.router)
app.include_router(trips.router)
app.include_router(classes.router)
app.include_router(tokens.router)
app.include_router(sync.router)


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
def health_check():
    """Vérifie que l'API est opérationnelle."""
    return {"status": "ok", "service": "SchoolTrack API", "version": "0.1.0"}
