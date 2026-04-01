"""
Router pour les écoles (US 6.6 — multi-tenancy).
GET /api/v1/schools  — liste (DIRECTION uniquement)
POST /api/v1/schools — créer une école (ADMIN_TECH uniquement)
"""

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.database import get_db
from app.dependencies import require_role
from app.models.school import School
from app.schemas.school import SchoolCreate, SchoolRead

router = APIRouter(prefix="/api/v1/schools", tags=["Écoles"])

_direction = require_role("DIRECTION", "ADMIN_TECH")
_admin     = require_role("ADMIN_TECH")


@router.get("/public", summary="Lister les écoles actives (public)")
def list_schools_public(db: Session = Depends(get_db)):
    """Retourne la liste des écoles actives (name + slug) sans authentification.
    Utilisé par l'app mobile pour le sélecteur d'école au login."""
    schools = db.execute(
        select(School.name, School.slug)
        .where(School.is_active == True)
        .order_by(School.name)
    ).all()
    return [{"name": row.name, "slug": row.slug} for row in schools]


@router.get("/{slug}/exists", summary="Verifier si une ecole existe (public)")
def school_exists(
    slug: str,
    db: Session = Depends(get_db),
):
    """Verifie si un slug d'ecole existe et est actif. Endpoint public (pas d'auth)."""
    school = db.execute(
        select(School).where(School.slug == slug, School.is_active == True)
    ).scalar_one_or_none()
    if not school:
        raise HTTPException(status_code=404, detail="Ecole introuvable")
    return {"slug": school.slug, "name": school.name}


@router.get("", response_model=list[SchoolRead], summary="Lister les écoles")
def list_schools(
    _=Depends(_direction),
    db: Session = Depends(get_db),
):
    """Retourne toutes les écoles actives."""
    schools = db.execute(
        select(School).where(School.is_active == True).order_by(School.name)
    ).scalars().all()
    return schools


@router.post("", response_model=SchoolRead, status_code=201, summary="Créer une école")
def create_school(
    data: SchoolCreate,
    _=Depends(_admin),
    db: Session = Depends(get_db),
):
    """Crée une nouvelle école. Slug doit être unique."""
    school = School(name=data.name, slug=data.slug)
    db.add(school)
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(status_code=409, detail=f"Le slug '{data.slug}' est déjà utilisé.")
    db.refresh(school)
    return school
