"""
Router pour la gestion des classes scolaires (US 1.3).
"""

import uuid
from typing import List

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.database import get_db
from app.schemas.school_class import (
    ClassCreate,
    ClassResponse,
    ClassStudentsAssign,
    ClassTeachersAssign,
    ClassUpdate,
)
from app.services import class_service

router = APIRouter(prefix="/api/v1/classes", tags=["Classes"])


@router.post("", response_model=ClassResponse, status_code=201, summary="Créer une classe")
def create_class(data: ClassCreate, db: Session = Depends(get_db)):
    """Crée une nouvelle classe scolaire avec un nom unique."""
    try:
        return class_service.create_class(db, data)
    except ValueError as e:
        raise HTTPException(status_code=409, detail=str(e))


@router.get("", response_model=List[ClassResponse], summary="Lister les classes")
def list_classes(db: Session = Depends(get_db)):
    """Retourne toutes les classes avec leur nombre d'élèves et d'enseignants."""
    return class_service.get_classes(db)


@router.get("/{class_id}", response_model=ClassResponse, summary="Détail d'une classe")
def get_class(class_id: uuid.UUID, db: Session = Depends(get_db)):
    school_class = class_service.get_class(db, class_id)
    if school_class is None:
        raise HTTPException(status_code=404, detail="Classe introuvable.")
    return school_class


@router.put("/{class_id}", response_model=ClassResponse, summary="Modifier une classe")
def update_class(class_id: uuid.UUID, data: ClassUpdate, db: Session = Depends(get_db)):
    try:
        result = class_service.update_class(db, class_id, data)
    except ValueError as e:
        raise HTTPException(status_code=409, detail=str(e))
    if result is None:
        raise HTTPException(status_code=404, detail="Classe introuvable.")
    return result


@router.delete("/{class_id}", status_code=204, summary="Supprimer une classe")
def delete_class(class_id: uuid.UUID, db: Session = Depends(get_db)):
    """
    Supprime une classe définitivement.
    Bloqué si des élèves participent à un voyage planifié ou en cours.
    """
    try:
        success = class_service.delete_class(db, class_id)
    except ValueError as e:
        raise HTTPException(status_code=409, detail=str(e))
    if not success:
        raise HTTPException(status_code=404, detail="Classe introuvable.")


# --- Gestion des élèves ---

@router.post("/{class_id}/students", response_model=ClassResponse, summary="Assigner des élèves")
def assign_students(class_id: uuid.UUID, data: ClassStudentsAssign, db: Session = Depends(get_db)):
    """Assigne un ou plusieurs élèves à une classe. Les doublons sont ignorés."""
    try:
        return class_service.assign_students(db, class_id, data)
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))


@router.delete("/{class_id}/students/{student_id}", status_code=204, summary="Retirer un élève")
def remove_student(class_id: uuid.UUID, student_id: uuid.UUID, db: Session = Depends(get_db)):
    """Retire un élève d'une classe."""
    success = class_service.remove_student(db, class_id, student_id)
    if not success:
        raise HTTPException(status_code=404, detail="Lien classe-élève introuvable.")


# --- Gestion des enseignants ---

@router.post("/{class_id}/teachers", response_model=ClassResponse, summary="Assigner des enseignants")
def assign_teachers(class_id: uuid.UUID, data: ClassTeachersAssign, db: Session = Depends(get_db)):
    """Assigne un ou plusieurs enseignants à une classe. Les doublons sont ignorés."""
    try:
        return class_service.assign_teachers(db, class_id, data)
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))


@router.delete("/{class_id}/teachers/{teacher_id}", status_code=204, summary="Retirer un enseignant")
def remove_teacher(class_id: uuid.UUID, teacher_id: uuid.UUID, db: Session = Depends(get_db)):
    """Retire un enseignant d'une classe."""
    success = class_service.remove_teacher(db, class_id, teacher_id)
    if not success:
        raise HTTPException(status_code=404, detail="Lien classe-enseignant introuvable.")
