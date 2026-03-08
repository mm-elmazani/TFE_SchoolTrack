"""
Router d'authentification (US 6.1 + US 6.2 + US 6.4).
Endpoints : login, register, refresh, 2FA, me, change-password.
Audit logging sur toutes les actions sensibles.
"""

from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy.orm import Session

from app.database import get_db
from app.dependencies import get_current_user, log_audit, require_role
from app.models.user import User
from app.schemas.auth import (
    ChangePasswordRequest,
    Enable2FAResponse,
    LoginRequest,
    MessageResponse,
    RefreshRequest,
    RegisterRequest,
    TokenResponse,
    UserInfo,
    Verify2FARequest,
)
from app.services.auth_service import (
    AccountLockedError,
    AuthError,
    TwoFactorRequiredError,
    authenticate_user,
    change_password,
    create_access_token,
    create_refresh_token,
    disable_2fa,
    enable_2fa,
    hash_password,
    refresh_access_token,
    register_user,
    verify_and_activate_2fa,
)

_admin = require_role("DIRECTION", "ADMIN_TECH")

router = APIRouter(prefix="/api/v1/auth", tags=["Authentification"])


# ---------------------------------------------------------------------------
# POST /login
# ---------------------------------------------------------------------------
@router.post("/login", response_model=TokenResponse)
def login(body: LoginRequest, request: Request, db: Session = Depends(get_db)):
    """Authentifie un utilisateur et retourne un couple access/refresh token."""
    _ip = request.client.host if request.client else None
    _ua = request.headers.get("user-agent")

    try:
        user = authenticate_user(db, body.email, body.password, body.totp_code)
    except AccountLockedError as e:
        log_audit(
            db, user_id=None, action="LOGIN_LOCKED",
            resource_type="AUTH", ip_address=_ip, user_agent=_ua,
            details={"email": body.email},
        )
        raise HTTPException(status_code=423, detail=str(e))
    except TwoFactorRequiredError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))
    except AuthError as e:
        log_audit(
            db, user_id=None, action="LOGIN_FAILED",
            resource_type="AUTH", ip_address=_ip, user_agent=_ua,
            details={"email": body.email},
        )
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail=str(e))

    log_audit(
        db, user_id=user.id, action="LOGIN_SUCCESS",
        resource_type="AUTH", ip_address=_ip, user_agent=_ua,
        details={"email": user.email, "role": user.role},
    )

    return TokenResponse(
        access_token=create_access_token(user),
        refresh_token=create_refresh_token(user),
        user=UserInfo.model_validate(user),
    )


# ---------------------------------------------------------------------------
# POST /register
# ---------------------------------------------------------------------------
@router.post("/register", response_model=UserInfo, status_code=status.HTTP_201_CREATED)
def register(
    body: RegisterRequest,
    current_user: User = Depends(_admin),
    db: Session = Depends(get_db),
):
    """Cree un nouvel utilisateur. Reserve a la Direction / Admin Tech (US 6.2)."""
    existing = db.query(User).filter(User.email == body.email).first()
    if existing:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Un utilisateur avec cet email existe deja",
        )

    user = register_user(
        db=db,
        email=body.email,
        password_hash=hash_password(body.password),
        first_name=body.first_name,
        last_name=body.last_name,
        role=body.role,
    )
    return UserInfo.model_validate(user)


# ---------------------------------------------------------------------------
# POST /refresh
# ---------------------------------------------------------------------------
@router.post("/refresh", response_model=TokenResponse)
def refresh(body: RefreshRequest, db: Session = Depends(get_db)):
    """Renouvelle les tokens a partir d'un refresh token valide."""
    try:
        user = refresh_access_token(db, body.refresh_token)
    except AuthError as e:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail=str(e))

    return TokenResponse(
        access_token=create_access_token(user),
        refresh_token=create_refresh_token(user),
        user=UserInfo.model_validate(user),
    )


# ---------------------------------------------------------------------------
# GET /me
# ---------------------------------------------------------------------------
@router.get("/me", response_model=UserInfo)
def me(current_user: User = Depends(get_current_user)):
    """Retourne les informations de l'utilisateur connecte."""
    return UserInfo.model_validate(current_user)


# ---------------------------------------------------------------------------
# POST /enable-2fa
# ---------------------------------------------------------------------------
@router.post("/enable-2fa", response_model=Enable2FAResponse)
def enable_two_factor(
    request: Request,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Genere un secret TOTP et retourne le QR code URI pour l'app authenticator."""
    if current_user.is_2fa_enabled:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="2FA deja active",
        )
    secret, uri = enable_2fa(db, current_user)

    log_audit(
        db, user_id=current_user.id, action="2FA_INITIATED",
        resource_type="AUTH",
        ip_address=request.client.host if request.client else None,
        user_agent=request.headers.get("user-agent"),
    )

    return Enable2FAResponse(secret=secret, provisioning_uri=uri)


# ---------------------------------------------------------------------------
# POST /verify-2fa
# ---------------------------------------------------------------------------
@router.post("/verify-2fa", response_model=MessageResponse)
def verify_two_factor(
    body: Verify2FARequest,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Verifie le code TOTP et active definitivement le 2FA."""
    success = verify_and_activate_2fa(db, current_user, body.totp_code)
    if not success:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Code 2FA invalide",
        )

    log_audit(
        db, user_id=current_user.id, action="2FA_ENABLED",
        resource_type="AUTH",
        ip_address=request.client.host if request.client else None,
        user_agent=request.headers.get("user-agent"),
    )

    return MessageResponse(message="2FA active avec succes")


# ---------------------------------------------------------------------------
# POST /disable-2fa
# ---------------------------------------------------------------------------
@router.post("/disable-2fa", response_model=MessageResponse)
def disable_two_factor(
    request: Request,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Desactive le 2FA pour l'utilisateur connecte."""
    if not current_user.is_2fa_enabled:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="2FA non active",
        )
    disable_2fa(db, current_user)

    log_audit(
        db, user_id=current_user.id, action="2FA_DISABLED",
        resource_type="AUTH",
        ip_address=request.client.host if request.client else None,
        user_agent=request.headers.get("user-agent"),
    )

    return MessageResponse(message="2FA desactive")


# ---------------------------------------------------------------------------
# POST /change-password
# ---------------------------------------------------------------------------
@router.post("/change-password", response_model=MessageResponse)
def change_user_password(
    body: ChangePasswordRequest,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Change le mot de passe de l'utilisateur connecte."""
    _ip = request.client.host if request.client else None
    _ua = request.headers.get("user-agent")

    try:
        change_password(db, current_user, body.current_password, hash_password(body.new_password))
    except AuthError as e:
        log_audit(
            db, user_id=current_user.id, action="PASSWORD_CHANGE_FAILED",
            resource_type="AUTH", ip_address=_ip, user_agent=_ua,
        )
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))

    log_audit(
        db, user_id=current_user.id, action="PASSWORD_CHANGED",
        resource_type="AUTH", ip_address=_ip, user_agent=_ua,
    )

    return MessageResponse(message="Mot de passe modifie avec succes")
