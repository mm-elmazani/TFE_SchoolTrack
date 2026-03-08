"""
Router pour les élèves (US 1.1, US 1.3, US 6.2, US 6.4).
Lecture : tous les utilisateurs authentifies.
Ecriture (create/update/delete/import) : DIRECTION et ADMIN_TECH uniquement.
Audit logging sur toutes les actions d'ecriture.
"""

import uuid
from typing import List

from fastapi import APIRouter, Depends, File, HTTPException, Request, UploadFile
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.database import get_db
from app.dependencies import get_current_user, log_audit, require_role
from app.models.student import Student
from app.models.user import User
from app.schemas.student import StudentCreate, StudentImportReport, StudentResponse, StudentUpdate
from app.services.student_import import parse_and_import_csv

router = APIRouter(prefix="/api/v1/students", tags=["Élèves"])

_admin = require_role("DIRECTION", "ADMIN_TECH")


@router.get("", response_model=List[StudentResponse], summary="Lister tous les élèves")
def list_students(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Retourne tous les eleves tries alphabetiquement par nom puis prenom."""
    students = db.execute(select(Student)).scalars().all()
    students = sorted(students, key=lambda s: ((s.last_name or "").lower(), (s.first_name or "").lower()))
    return students


@router.post("", response_model=StudentResponse, status_code=201, summary="Créer un élève manuellement")
def create_student(
    data: StudentCreate,
    request: Request,
    current_user: User = Depends(_admin),
    db: Session = Depends(get_db),
):
    """Crée un élève manuellement (hors import CSV)."""
    student = Student(
        first_name=data.first_name,
        last_name=data.last_name,
        email=data.email,
    )
    db.add(student)
    db.commit()
    db.refresh(student)

    log_audit(
        db, user_id=current_user.id, action="STUDENT_CREATED",
        resource_type="STUDENT", resource_id=student.id,
        ip_address=request.client.host if request.client else None,
        user_agent=request.headers.get("user-agent"),
        details={"first_name": data.first_name, "last_name": data.last_name},
    )

    return student


@router.put("/{student_id}", response_model=StudentResponse, summary="Modifier un élève")
def update_student(
    student_id: uuid.UUID,
    data: StudentUpdate,
    request: Request,
    current_user: User = Depends(_admin),
    db: Session = Depends(get_db),
):
    """Met à jour les champs fournis d'un élève. Les champs absents ne sont pas modifiés."""
    student = db.get(Student, student_id)
    if student is None:
        raise HTTPException(status_code=404, detail="Élève introuvable.")

    update_data = data.model_dump(exclude_unset=True)
    for field, value in update_data.items():
        setattr(student, field, value)

    db.commit()
    db.refresh(student)

    log_audit(
        db, user_id=current_user.id, action="STUDENT_UPDATED",
        resource_type="STUDENT", resource_id=student.id,
        ip_address=request.client.host if request.client else None,
        user_agent=request.headers.get("user-agent"),
        details={"fields": list(update_data.keys())},
    )

    return student


@router.delete("/{student_id}", status_code=204, summary="Supprimer un élève")
def delete_student(
    student_id: uuid.UUID,
    request: Request,
    current_user: User = Depends(_admin),
    db: Session = Depends(get_db),
):
    """Supprime définitivement un élève. Les présences et assignations liées sont supprimées en cascade."""
    student = db.get(Student, student_id)
    if student is None:
        raise HTTPException(status_code=404, detail="Élève introuvable.")

    log_audit(
        db, user_id=current_user.id, action="STUDENT_DELETED",
        resource_type="STUDENT", resource_id=student.id,
        ip_address=request.client.host if request.client else None,
        user_agent=request.headers.get("user-agent"),
        details={"first_name": student.first_name, "last_name": student.last_name},
    )

    db.delete(student)
    db.commit()


ALLOWED_CONTENT_TYPES = {"text/csv", "text/plain", "application/vnd.ms-excel"}
MAX_FILE_SIZE_MB = 5


@router.post("/upload", response_model=StudentImportReport, summary="Importer des élèves via CSV")
async def upload_students(
    request: Request,
    file: UploadFile = File(...),
    current_user: User = Depends(_admin),
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

    log_audit(
        db, user_id=current_user.id, action="STUDENTS_IMPORTED",
        resource_type="STUDENT",
        ip_address=request.client.host if request.client else None,
        user_agent=request.headers.get("user-agent"),
        details={"filename": file.filename, "created": report.created_count, "errors": report.error_count},
    )

    return report
