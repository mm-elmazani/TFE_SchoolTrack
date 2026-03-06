"""
Router de gestion des utilisateurs (US 6.1).
La Direction peut lister et creer des comptes enseignants/observateurs.
"""

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.database import get_db
from app.dependencies import get_current_user
from app.models.user import User
from app.schemas.auth import RegisterRequest, UserInfo
from app.services.auth_service import hash_password, register_user

router = APIRouter(prefix="/api/v1/users", tags=["Utilisateurs"])


@router.get("", response_model=list[UserInfo])
def list_users(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Liste tous les utilisateurs. Reserve a la Direction."""
    if current_user.role not in ("DIRECTION", "ADMIN_TECH"):
        raise HTTPException(status_code=403, detail="Acces reserve a la Direction")
    users = db.query(User).order_by(User.last_name, User.first_name).all()
    return [UserInfo.model_validate(u) for u in users]


@router.post("", response_model=UserInfo, status_code=status.HTTP_201_CREATED)
def create_user(
    body: RegisterRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Cree un nouvel utilisateur. Reserve a la Direction."""
    if current_user.role not in ("DIRECTION", "ADMIN_TECH"):
        raise HTTPException(status_code=403, detail="Acces reserve a la Direction")

    existing = db.query(User).filter(User.email == body.email).first()
    if existing:
        raise HTTPException(status_code=409, detail="Un utilisateur avec cet email existe deja")

    user = register_user(
        db=db,
        email=body.email,
        password_hash=hash_password(body.password),
        first_name=body.first_name,
        last_name=body.last_name,
        role=body.role,
    )
    return UserInfo.model_validate(user)


@router.delete("/{user_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_user(
    user_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Supprime un utilisateur. Reserve a la Direction. Ne peut pas se supprimer soi-meme."""
    if current_user.role not in ("DIRECTION", "ADMIN_TECH"):
        raise HTTPException(status_code=403, detail="Acces reserve a la Direction")

    if str(current_user.id) == user_id:
        raise HTTPException(status_code=400, detail="Impossible de supprimer votre propre compte")

    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="Utilisateur introuvable")

    db.delete(user)
    db.commit()
