"""
Router pour la gestion des classes scolaires (US 1.3, US 6.2, US 6.4).
Lecture : tous les utilisateurs authentifies.
Ecriture : DIRECTION et ADMIN_TECH.
Audit logging sur toutes les actions d'ecriture.
"""

import uuid
from typing import List

from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.orm import Session

from app.database import get_db
from app.dependencies import get_client_ip, get_current_user, log_audit, require_role
from app.models.user import User
from app.schemas.school_class import (
    ClassCreate,
    ClassResponse,
    ClassStudentsAssign,
    ClassTeachersAssign,
    ClassUpdate,
)
from app.services import class_service

router = APIRouter(prefix="/api/v1/classes", tags=["Classes"])

_admin = require_role("DIRECTION", "ADMIN_TECH")


@router.post("", response_model=ClassResponse, status_code=201, summary="Créer une classe")
def create_class(
    data: ClassCreate,
    request: Request,
    current_user: User = Depends(_admin),
    db: Session = Depends(get_db),
):
    """Crée une nouvelle classe scolaire avec un nom unique."""
    try:
        result = class_service.create_class(db, data, school_id=current_user.school_id)
    except ValueError as e:
        raise HTTPException(status_code=409, detail=str(e))

    log_audit(
        db, user_id=current_user.id, action="CLASS_CREATED",
        resource_type="CLASS", resource_id=result.id,
        ip_address=get_client_ip(request),
        user_agent=request.headers.get("user-agent"),
        details={"name": data.name},
    )

    return result


@router.get("", response_model=List[ClassResponse], summary="Lister les classes")
def list_classes(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Retourne toutes les classes avec leur nombre d'élèves et d'enseignants."""
    return class_service.get_classes(db, school_id=current_user.school_id)


@router.get("/{class_id}", response_model=ClassResponse, summary="Détail d'une classe")
def get_class(
    class_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    school_class = class_service.get_class(db, class_id, school_id=current_user.school_id)
    if school_class is None:
        raise HTTPException(status_code=404, detail="Classe introuvable.")
    return school_class


@router.put("/{class_id}", response_model=ClassResponse, summary="Modifier une classe")
def update_class(
    class_id: uuid.UUID,
    data: ClassUpdate,
    request: Request,
    current_user: User = Depends(_admin),
    db: Session = Depends(get_db),
):
    try:
        result = class_service.update_class(db, class_id, data, school_id=current_user.school_id)
    except ValueError as e:
        raise HTTPException(status_code=409, detail=str(e))
    if result is None:
        raise HTTPException(status_code=404, detail="Classe introuvable.")

    log_audit(
        db, user_id=current_user.id, action="CLASS_UPDATED",
        resource_type="CLASS", resource_id=class_id,
        ip_address=get_client_ip(request),
        user_agent=request.headers.get("user-agent"),
        details={"fields": list(data.model_dump(exclude_unset=True).keys())},
    )

    return result


@router.delete("/{class_id}", status_code=204, summary="Supprimer une classe")
def delete_class(
    class_id: uuid.UUID,
    request: Request,
    current_user: User = Depends(_admin),
    db: Session = Depends(get_db),
):
    """
    Supprime une classe définitivement.
    Bloqué si des élèves participent à un voyage planifié ou en cours.
    """
    try:
        success = class_service.delete_class(db, class_id, school_id=current_user.school_id)
    except ValueError as e:
        raise HTTPException(status_code=409, detail=str(e))
    if not success:
        raise HTTPException(status_code=404, detail="Classe introuvable.")

    log_audit(
        db, user_id=current_user.id, action="CLASS_DELETED",
        resource_type="CLASS", resource_id=class_id,
        ip_address=get_client_ip(request),
        user_agent=request.headers.get("user-agent"),
    )


# --- Gestion des élèves ---

@router.get("/{class_id}/students", response_model=List[uuid.UUID], summary="Élèves d'une classe")
def list_class_students(
    class_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Retourne les IDs des élèves assignés à une classe."""
    from sqlalchemy import select
    from app.models.school_class import ClassStudent
    ids = db.execute(
        select(ClassStudent.student_id).where(ClassStudent.class_id == class_id)
    ).scalars().all()
    return ids


@router.post("/{class_id}/students", response_model=ClassResponse, summary="Assigner des élèves")
def assign_students(
    class_id: uuid.UUID,
    data: ClassStudentsAssign,
    request: Request,
    current_user: User = Depends(_admin),
    db: Session = Depends(get_db),
):
    """Assigne un ou plusieurs élèves à une classe. Les doublons sont ignorés."""
    try:
        result = class_service.assign_students(db, class_id, data, school_id=current_user.school_id)
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))

    log_audit(
        db, user_id=current_user.id, action="CLASS_STUDENTS_ASSIGNED",
        resource_type="CLASS", resource_id=class_id,
        ip_address=get_client_ip(request),
        user_agent=request.headers.get("user-agent"),
        details={"student_count": len(data.student_ids)},
    )

    return result


@router.delete("/{class_id}/students/{student_id}", status_code=204, summary="Retirer un élève")
def remove_student(
    class_id: uuid.UUID,
    student_id: uuid.UUID,
    request: Request,
    current_user: User = Depends(_admin),
    db: Session = Depends(get_db),
):
    """Retire un élève d'une classe."""
    success = class_service.remove_student(db, class_id, student_id, school_id=current_user.school_id)
    if not success:
        raise HTTPException(status_code=404, detail="Lien classe-élève introuvable.")

    log_audit(
        db, user_id=current_user.id, action="CLASS_STUDENT_REMOVED",
        resource_type="CLASS", resource_id=class_id,
        ip_address=get_client_ip(request),
        user_agent=request.headers.get("user-agent"),
        details={"student_id": str(student_id)},
    )


# --- Gestion des enseignants ---

@router.post("/{class_id}/teachers", response_model=ClassResponse, summary="Assigner des enseignants")
def assign_teachers(
    class_id: uuid.UUID,
    data: ClassTeachersAssign,
    request: Request,
    current_user: User = Depends(_admin),
    db: Session = Depends(get_db),
):
    """Assigne un ou plusieurs enseignants à une classe. Les doublons sont ignorés."""
    try:
        result = class_service.assign_teachers(db, class_id, data, school_id=current_user.school_id)
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))

    log_audit(
        db, user_id=current_user.id, action="CLASS_TEACHERS_ASSIGNED",
        resource_type="CLASS", resource_id=class_id,
        ip_address=get_client_ip(request),
        user_agent=request.headers.get("user-agent"),
        details={"teacher_count": len(data.teacher_ids)},
    )

    return result


@router.delete("/{class_id}/teachers/{teacher_id}", status_code=204, summary="Retirer un enseignant")
def remove_teacher(
    class_id: uuid.UUID,
    teacher_id: uuid.UUID,
    request: Request,
    current_user: User = Depends(_admin),
    db: Session = Depends(get_db),
):
    """Retire un enseignant d'une classe."""
    success = class_service.remove_teacher(db, class_id, teacher_id, school_id=current_user.school_id)
    if not success:
        raise HTTPException(status_code=404, detail="Lien classe-enseignant introuvable.")

    log_audit(
        db, user_id=current_user.id, action="CLASS_TEACHER_REMOVED",
        resource_type="CLASS", resource_id=class_id,
        ip_address=get_client_ip(request),
        user_agent=request.headers.get("user-agent"),
        details={"teacher_id": str(teacher_id)},
    )
