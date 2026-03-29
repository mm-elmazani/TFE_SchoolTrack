"""
Dependances FastAPI partagees (US 6.1 + US 6.2).
get_current_user : extraction et validation du JWT depuis le header Authorization.
require_role : fabrique de dependances pour restreindre un endpoint a certains roles.
log_audit : journalise une action dans la table audit_logs (RGPD).
"""

from typing import Callable

from fastapi import Depends, HTTPException, Request, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jose import JWTError
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.user import User
from app.services.auth_service import decode_token

security = HTTPBearer()


def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(security),
    db: Session = Depends(get_db),
) -> User:
    """Dependance FastAPI : extrait l'utilisateur courant depuis le JWT Bearer."""
    token = credentials.credentials
    try:
        payload = decode_token(token)
    except JWTError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token invalide ou expire",
            headers={"WWW-Authenticate": "Bearer"},
        )

    if payload.get("type") != "access":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token invalide (type attendu: access)",
            headers={"WWW-Authenticate": "Bearer"},
        )

    user_id = payload.get("sub")
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Utilisateur introuvable",
            headers={"WWW-Authenticate": "Bearer"},
        )

    return user


# ---------------------------------------------------------------------------
# US 6.2 — Fabrique de dependance role
# ---------------------------------------------------------------------------

def require_role(*allowed_roles: str) -> Callable:
    """
    Retourne une dependance FastAPI qui verifie que l'utilisateur connecte
    possede l'un des roles autorises. Leve HTTP 403 sinon.

    Usage dans un router :
        current_user: User = Depends(require_role("DIRECTION", "ADMIN_TECH"))
    """
    def _role_checker(current_user: User = Depends(get_current_user)) -> User:
        if current_user.role not in allowed_roles:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"Acces reserve aux roles : {', '.join(allowed_roles)}",
            )
        return current_user
    return _role_checker


# ---------------------------------------------------------------------------
# US 6.2 — IP source reelle (derriere Traefik)
# ---------------------------------------------------------------------------

def get_client_ip(request: Request) -> str | None:
    """Extrait l'IP reelle du client depuis X-Forwarded-For (proxy Traefik) ou request.client."""
    forwarded = request.headers.get("x-forwarded-for")
    if forwarded:
        return forwarded.split(",")[0].strip()
    return request.client.host if request.client else None


# ---------------------------------------------------------------------------
# US 6.2 — Audit log
# ---------------------------------------------------------------------------

def log_audit(
    db: Session,
    *,
    user_id,
    action: str,
    resource_type: str | None = None,
    resource_id=None,
    ip_address: str | None = None,
    user_agent: str | None = None,
    details: dict | None = None,
) -> None:
    """Insere une ligne dans audit_logs (table deja existante dans init.sql)."""
    from sqlalchemy import text

    db.execute(
        text(
            "INSERT INTO audit_logs (user_id, action, resource_type, resource_id, "
            "ip_address, user_agent, details) "
            "VALUES (:uid, :action, :rtype, :rid, :ip, :ua, :details)"
        ),
        {
            "uid": str(user_id) if user_id else None,
            "action": action,
            "rtype": resource_type,
            "rid": str(resource_id) if resource_id else None,
            "ip": ip_address,
            "ua": user_agent,
            "details": __import__("json").dumps(details) if details else None,
        },
    )
    db.commit()
