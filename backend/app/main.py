"""
Point d'entrée principal de l'API SchoolTrack.
Démarrage : uvicorn app.main:app --reload
"""

from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

import app.models  # noqa: F401 — enregistre tous les modèles SQLAlchemy dans les métadonnées
from app.routers import classes, students, sync, tokens, trips
from app.scheduler import start_scheduler, stop_scheduler


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

# CORS — en dev, on autorise tout (à restreindre en production)
# allow_credentials=False obligatoire quand allow_origins=["*"] (standard CORS)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)


app.include_router(students.router)
app.include_router(trips.router)
app.include_router(classes.router)
app.include_router(tokens.router)
app.include_router(sync.router)


@app.get("/api/health", tags=["Santé"])
def health_check():
    """Vérifie que l'API est opérationnelle."""
    return {"status": "ok", "service": "SchoolTrack API", "version": "0.1.0"}
