"""
Router pour les élèves.
US 1.1 : Import CSV (POST /api/v1/students/upload)
US 1.3 : Listage élèves (GET /api/v1/students)
         Création manuelle (POST /api/v1/students)
         Mise à jour (PUT /api/v1/students/{id})
         Suppression (DELETE /api/v1/students/{id})
"""

import uuid
from typing import List

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.student import Student
from app.schemas.student import StudentCreate, StudentImportReport, StudentResponse, StudentUpdate
from app.services.student_import import parse_and_import_csv

router = APIRouter(prefix="/api/v1/students", tags=["Élèves"])


@router.get("", response_model=List[StudentResponse], summary="Lister tous les élèves")
def list_students(db: Session = Depends(get_db)):
    """Retourne tous les élèves triés alphabétiquement par nom puis prénom."""
    students = db.execute(
        select(Student).order_by(Student.last_name, Student.first_name)
    ).scalars().all()
    return students


@router.post("", response_model=StudentResponse, status_code=201, summary="Créer un élève manuellement")
def create_student(data: StudentCreate, db: Session = Depends(get_db)):
    """Crée un élève manuellement (hors import CSV)."""
    student = Student(
        first_name=data.first_name,
        last_name=data.last_name,
        email=data.email,
    )
    db.add(student)
    db.commit()
    db.refresh(student)
    return student


@router.put("/{student_id}", response_model=StudentResponse, summary="Modifier un élève")
def update_student(student_id: uuid.UUID, data: StudentUpdate, db: Session = Depends(get_db)):
    """Met à jour les champs fournis d'un élève. Les champs absents ne sont pas modifiés."""
    student = db.get(Student, student_id)
    if student is None:
        raise HTTPException(status_code=404, detail="Élève introuvable.")

    update_data = data.model_dump(exclude_unset=True)
    for field, value in update_data.items():
        setattr(student, field, value)

    db.commit()
    db.refresh(student)
    return student


@router.delete("/{student_id}", status_code=204, summary="Supprimer un élève")
def delete_student(student_id: uuid.UUID, db: Session = Depends(get_db)):
    """Supprime définitivement un élève. Les présences et assignations liées sont supprimées en cascade."""
    student = db.get(Student, student_id)
    if student is None:
        raise HTTPException(status_code=404, detail="Élève introuvable.")

    db.delete(student)
    db.commit()


ALLOWED_CONTENT_TYPES = {"text/csv", "text/plain", "application/vnd.ms-excel"}
MAX_FILE_SIZE_MB = 5


@router.post("/upload", response_model=StudentImportReport, summary="Importer des élèves via CSV")
async def upload_students(
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
):
    """
    Importe une liste d'élèves depuis un fichier CSV.

    Format attendu du CSV :
    - Colonnes obligatoires : `nom`, `prenom`
    - Colonne optionnelle : `email`
    - Séparateur : virgule (`,`) ou point-virgule (`;`)
    - Encodage : UTF-8 (avec ou sans BOM)

    Retourne un rapport détaillant les insertions et les rejets.
    """
    # Validation du type de fichier
    if file.content_type not in ALLOWED_CONTENT_TYPES and not file.filename.endswith(".csv"):
        raise HTTPException(
            status_code=400,
            detail="Format invalide. Seuls les fichiers CSV sont acceptés."
        )

    content = await file.read()

    # Validation de la taille
    if len(content) > MAX_FILE_SIZE_MB * 1024 * 1024:
        raise HTTPException(
            status_code=400,
            detail=f"Fichier trop volumineux. Taille maximale : {MAX_FILE_SIZE_MB} Mo."
        )

    if not content:
        raise HTTPException(status_code=400, detail="Le fichier CSV est vide.")

    report = parse_and_import_csv(content, db)
    return report
