"""
Configuration de la connexion à la base de données PostgreSQL.
Utilise SQLAlchemy avec un moteur asynchrone.
"""

from sqlalchemy import create_engine
from sqlalchemy.orm import declarative_base
from sqlalchemy.orm import sessionmaker

from app.config import settings

# Moteur SQLAlchemy synchrone (on passera en async lors de l'ajout des endpoints)
engine = create_engine(settings.DATABASE_URL)

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

Base = declarative_base()


def get_db():
    """Dépendance FastAPI — fournit une session BDD et la ferme après usage."""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
