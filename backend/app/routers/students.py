"""
Router pour les élèves (US 1.1, US 1.3, US 6.2, US 6.4, US 6.5).
Lecture : tous les utilisateurs authentifies.
Ecriture (create/update/delete/import) : DIRECTION et ADMIN_TECH uniquement.
Audit logging sur toutes les actions d'ecriture.
Suppression logique (soft delete) pour conformite RGPD (US 6.5).
"""

import uuid
from datetime import datetime
from pathlib import Path
from typing import List

from fastapi import APIRouter, Depends, File, HTTPException, Query, Request, UploadFile
from fastapi.responses import FileResponse
from sqlalchemy import select, text
from sqlalchemy.orm import Session

from app.config import settings
from app.database import get_db
from app.dependencies import get_client_ip, get_current_user, log_audit, require_role
from app.models.student import Student
from app.models.user import User
from app.schemas.student import (
    StudentCreate, StudentGdprExport, StudentImportReport,
    StudentResponse, StudentUpdate,
)
from app.services.student_import import parse_and_import_csv, parse_and_import_excel

ALLOWED_IMAGE_TYPES = {"image/jpeg", "image/png", "image/webp"}
MAX_PHOTO_SIZE = 5 * 1024 * 1024  # 5 Mo

router = APIRouter(prefix="/api/v1/students", tags=["Élèves"])

_admin = require_role("DIRECTION", "ADMIN_TECH")


@router.get("", response_model=List[StudentResponse], summary="Lister tous les élèves")
def list_students(
    include_deleted: bool = Query(False, description="Inclure les eleves supprimes (RGPD)"),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Retourne tous les eleves tries alphabetiquement par nom puis prenom.
    Par defaut, les eleves supprimes logiquement sont exclus."""
    query = select(Student).where(Student.school_id == current_user.school_id)
    if not include_deleted:
        query = query.where(Student.is_deleted == False)  # noqa: E712
    students = db.execute(query).scalars().all()
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
        phone=data.phone,
        school_id=current_user.school_id,
    )
    db.add(student)
    db.commit()
    db.refresh(student)

    log_audit(
        db, user_id=current_user.id, action="STUDENT_CREATED",
        resource_type="STUDENT", resource_id=student.id,
        ip_address=get_client_ip(request),
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
    if getattr(student, "is_deleted", False):
        raise HTTPException(status_code=410, detail="Élève supprimé. Rectification RGPD non disponible.")

    update_data = data.model_dump(exclude_unset=True)
    for field, value in update_data.items():
        setattr(student, field, value)

    db.commit()
    db.refresh(student)

    log_audit(
        db, user_id=current_user.id, action="STUDENT_UPDATED",
        resource_type="STUDENT", resource_id=student.id,
        ip_address=get_client_ip(request),
        user_agent=request.headers.get("user-agent"),
        details={"fields": list(update_data.keys())},
    )

    return student


@router.post("/{student_id}/photo", response_model=StudentResponse, summary="Uploader la photo d'un élève")
async def upload_student_photo(
    student_id: uuid.UUID,
    request: Request,
    file: UploadFile = File(...),
    current_user: User = Depends(_admin),
    db: Session = Depends(get_db),
):
    """Upload ou remplace la photo d'un élève. Formats acceptés : JPEG, PNG, WebP. Max 5 Mo."""
    student = db.get(Student, student_id)
    if student is None:
        raise HTTPException(status_code=404, detail="Élève introuvable.")
    if getattr(student, "is_deleted", False):
        raise HTTPException(status_code=410, detail="Élève supprimé.")

    if file.content_type not in ALLOWED_IMAGE_TYPES:
        raise HTTPException(status_code=415, detail="Format non supporté. Utilisez JPEG, PNG ou WebP.")

    content = await file.read()
    if len(content) > MAX_PHOTO_SIZE:
        raise HTTPException(status_code=413, detail="Fichier trop volumineux (max 5 Mo).")

    ext = file.content_type.split("/")[-1].replace("jpeg", "jpg")
    filename = f"{student_id}.{ext}"
    dest = Path(settings.MEDIA_DIR, "students", filename)
    dest.write_bytes(content)

    # Stockage du chemin relatif (pas une URL publique — servi via endpoint protégé)
    student.photo_url = f"students/{filename}"
    db.commit()
    db.refresh(student)

    log_audit(
        db, user_id=current_user.id, action="STUDENT_UPDATED",
        resource_type="STUDENT", resource_id=student.id,
        ip_address=get_client_ip(request),
        user_agent=request.headers.get("user-agent"),
        details={"fields": ["photo_url"]},
    )

    return student


@router.get("/{student_id}/photo", summary="Télécharger la photo d'un élève (authentifié)")
def get_student_photo(
    student_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Sert la photo d'un élève. Requiert un JWT valide (tous les rôles authentifiés)."""
    student = db.get(Student, student_id)
    if student is None or not student.photo_url:
        raise HTTPException(status_code=404, detail="Photo introuvable.")

    photo_path = Path(settings.MEDIA_DIR, student.photo_url)
    if not photo_path.exists():
        raise HTTPException(status_code=404, detail="Fichier photo introuvable.")

    return FileResponse(photo_path)


@router.delete("/{student_id}", status_code=204, summary="Supprimer un élève (soft delete RGPD)")
def delete_student(
    student_id: uuid.UUID,
    request: Request,
    current_user: User = Depends(_admin),
    db: Session = Depends(get_db),
):
    """Suppression logique d'un eleve (RGPD droit a l'effacement).
    L'eleve est marque is_deleted=True, les donnees sont conservees pour l'historique."""
    student = db.get(Student, student_id)
    if student is None:
        raise HTTPException(status_code=404, detail="Élève introuvable.")
    if getattr(student, "is_deleted", False):
        raise HTTPException(status_code=410, detail="Élève déjà supprimé.")

    student.is_deleted = True
    student.deleted_at = datetime.utcnow()
    student.deleted_by = current_user.id
    db.commit()

    log_audit(
        db, user_id=current_user.id, action="STUDENT_SOFT_DELETED",
        resource_type="STUDENT", resource_id=student.id,
        ip_address=get_client_ip(request),
        user_agent=request.headers.get("user-agent"),
        details={"first_name": student.first_name, "last_name": student.last_name},
    )


@router.get(
    "/{student_id}/data-export",
    response_model=StudentGdprExport,
    summary="Export RGPD des donnees personnelles d'un eleve",
)
def export_student_data(
    student_id: uuid.UUID,
    request: Request,
    current_user: User = Depends(_admin),
    db: Session = Depends(get_db),
):
    """RGPD droit d'acces (art. 15) : exporte toutes les donnees personnelles
    d'un eleve sous forme JSON structuree."""
    student = db.get(Student, student_id)
    if student is None:
        raise HTTPException(status_code=404, detail="Élève introuvable.")

    sid = str(student_id)

    # Donnees personnelles
    student_data = {
        "id": sid,
        "first_name": student.first_name,
        "last_name": student.last_name,
        "email": student.email,
        "photo_url": student.photo_url,
        "parent_consent": student.parent_consent,
        "is_deleted": student.is_deleted,
        "created_at": str(student.created_at) if student.created_at else None,
        "updated_at": str(student.updated_at) if student.updated_at else None,
        "deleted_at": str(student.deleted_at) if student.deleted_at else None,
    }

    # Classes
    classes_rows = db.execute(
        text("""
            SELECT c.id, c.name, cs.enrolled_at
            FROM class_students cs
            JOIN classes c ON c.id = cs.class_id
            WHERE cs.student_id = :sid
        """), {"sid": sid},
    ).fetchall()
    classes = [
        {"class_id": str(r[0]), "class_name": r[1], "enrolled_at": str(r[2]) if r[2] else None}
        for r in classes_rows
    ]

    # Sorties scolaires
    trips_rows = db.execute(
        text("""
            SELECT t.id, t.destination, t.date, ts.added_at
            FROM trip_students ts
            JOIN trips t ON t.id = ts.trip_id
            WHERE ts.student_id = :sid
        """), {"sid": sid},
    ).fetchall()
    trips = [
        {
            "trip_id": str(r[0]), "destination": r[1],
            "date": str(r[2]) if r[2] else None,
            "added_at": str(r[3]) if r[3] else None,
        }
        for r in trips_rows
    ]

    # Presences
    att_rows = db.execute(
        text("""
            SELECT id, trip_id, checkpoint_id, scanned_at, scan_method,
                   is_manual, justification, comment
            FROM attendances
            WHERE student_id = :sid
            ORDER BY scanned_at
        """), {"sid": sid},
    ).fetchall()
    attendances = [
        {
            "id": str(r[0]), "trip_id": str(r[1]), "checkpoint_id": str(r[2]),
            "scanned_at": str(r[3]) if r[3] else None, "scan_method": r[4],
            "is_manual": r[5], "justification": r[6], "comment": r[7],
        }
        for r in att_rows
    ]

    # Assignations de tokens
    asgn_rows = db.execute(
        text("""
            SELECT id, token_uid, trip_id, assignment_type, assigned_at, released_at
            FROM assignments
            WHERE student_id = :sid
            ORDER BY assigned_at
        """), {"sid": sid},
    ).fetchall()
    assignments = [
        {
            "id": r[0], "token_uid": r[1], "trip_id": str(r[2]),
            "assignment_type": r[3],
            "assigned_at": str(r[4]) if r[4] else None,
            "released_at": str(r[5]) if r[5] else None,
        }
        for r in asgn_rows
    ]

    # Alertes
    alert_rows = db.execute(
        text("""
            SELECT id, trip_id, alert_type, severity, message, status, created_at, resolved_at
            FROM alerts
            WHERE student_id = :sid
            ORDER BY created_at
        """), {"sid": sid},
    ).fetchall()
    alerts = [
        {
            "id": str(r[0]), "trip_id": str(r[1]), "alert_type": r[2],
            "severity": r[3], "message": r[4], "status": r[5],
            "created_at": str(r[6]) if r[6] else None,
            "resolved_at": str(r[7]) if r[7] else None,
        }
        for r in alert_rows
    ]

    log_audit(
        db, user_id=current_user.id, action="STUDENT_DATA_EXPORTED",
        resource_type="STUDENT", resource_id=student.id,
        ip_address=get_client_ip(request),
        user_agent=request.headers.get("user-agent"),
        details={"first_name": student.first_name, "last_name": student.last_name},
    )

    return StudentGdprExport(
        exported_at=datetime.utcnow().isoformat(),
        student=student_data,
        classes=classes,
        trips=trips,
        attendances=attendances,
        assignments=assignments,
        alerts=alerts,
    )


ALLOWED_CSV_TYPES = {"text/csv", "text/plain", "application/vnd.ms-excel"}
ALLOWED_EXCEL_TYPES = {
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    "application/vnd.ms-excel",
}
ALLOWED_CONTENT_TYPES = ALLOWED_CSV_TYPES | ALLOWED_EXCEL_TYPES
MAX_FILE_SIZE_MB = 5


def _is_excel_file(file: UploadFile) -> bool:
    """Détermine si le fichier uploadé est un Excel (.xlsx)."""
    if file.filename and file.filename.lower().endswith(".xlsx"):
        return True
    if file.content_type in ALLOWED_EXCEL_TYPES:
        return True
    return False


@router.post("/upload", response_model=StudentImportReport, summary="Importer des élèves via CSV ou Excel")
async def upload_students(
    request: Request,
    file: UploadFile = File(...),
    current_user: User = Depends(_admin),
    db: Session = Depends(get_db),
):
    """
    Importe une liste d'élèves depuis un fichier CSV ou Excel (.xlsx).

    Colonnes obligatoires : `nom`, `prenom` (ou alias : Prénom, Nom, etc.)
    Colonnes optionnelles : `email`/`mail`, `classe`, `telephone`/`GSM Élève`
    Les colonnes non reconnues sont ignorées.
    """
    filename = file.filename or ""
    is_csv = filename.lower().endswith(".csv")
    is_excel = filename.lower().endswith(".xlsx")

    if not is_csv and not is_excel and file.content_type not in ALLOWED_CONTENT_TYPES:
        raise HTTPException(
            status_code=400,
            detail="Format invalide. Fichiers acceptés : CSV (.csv) ou Excel (.xlsx)."
        )

    content = await file.read()

    if len(content) > MAX_FILE_SIZE_MB * 1024 * 1024:
        raise HTTPException(
            status_code=400,
            detail=f"Fichier trop volumineux. Taille maximale : {MAX_FILE_SIZE_MB} Mo."
        )

    if not content:
        raise HTTPException(status_code=400, detail="Le fichier est vide.")

    if _is_excel_file(file):
        report = parse_and_import_excel(content, db, school_id=current_user.school_id)
    else:
        report = parse_and_import_csv(content, db, school_id=current_user.school_id)

    log_audit(
        db, user_id=current_user.id, action="STUDENTS_IMPORTED",
        resource_type="STUDENT",
        ip_address=get_client_ip(request),
        user_agent=request.headers.get("user-agent"),
        details={"filename": file.filename, "created": report.inserted, "errors": report.rejected},
    )

    return report
