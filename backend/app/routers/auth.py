"""
Router d'authentification (US 6.1 + US 6.2 + US 6.4).
Endpoints : login, register, refresh, 2FA, me, change-password.
Audit logging sur toutes les actions sensibles.
"""

from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy.orm import Session

from app.database import get_db
from app.dependencies import get_client_ip, get_current_user, log_audit, require_role
from app.models.school import School
from app.models.user import User
from app.schemas.auth import (
    ChangePasswordRequest,
    Enable2FAResponse,
    ForgotPasswordRequest,
    LoginRequest,
    MessageResponse,
    RefreshRequest,
    RegisterRequest,
    ResetPasswordRequest,
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
    enable_2fa_email,
    hash_password,
    refresh_access_token,
    register_user,
    request_password_reset,
    reset_password_with_token,
    send_email_otp,
    verify_and_activate_2fa,
    verify_and_activate_2fa_email,
)

_admin = require_role("DIRECTION", "ADMIN_TECH")

router = APIRouter(prefix="/api/v1/auth", tags=["Authentification"])


# ---------------------------------------------------------------------------
# POST /login
# ---------------------------------------------------------------------------
@router.post("/login", response_model=TokenResponse)
def login(body: LoginRequest, request: Request, db: Session = Depends(get_db)):
    """Authentifie un utilisateur et retourne un couple access/refresh token."""
    _ip = get_client_ip(request)
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

    # Verification du slug ecole (si fourni par le frontend)
    school_slug = None
    if body.school_slug:
        school = db.query(School).filter(School.id == user.school_id).first()
        if not school or school.slug != body.school_slug:
            log_audit(
                db, user_id=user.id, action="LOGIN_FAILED",
                resource_type="AUTH", ip_address=_ip, user_agent=_ua,
                details={"email": body.email, "reason": "school_slug_mismatch",
                         "expected_slug": body.school_slug},
            )
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Vous n'appartenez pas a cette ecole.",
            )
        school_slug = school.slug
    else:
        school = db.query(School).filter(School.id == user.school_id).first()
        school_slug = school.slug if school else None

    log_audit(
        db, user_id=user.id, action="LOGIN_SUCCESS",
        resource_type="AUTH", ip_address=_ip, user_agent=_ua,
        details={"email": user.email, "role": user.role},
    )

    user_info = UserInfo.model_validate(user)
    user_info.school_slug = school_slug

    return TokenResponse(
        access_token=create_access_token(user),
        refresh_token=create_refresh_token(user),
        user=user_info,
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
        ip_address=get_client_ip(request),
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
        ip_address=get_client_ip(request),
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
        ip_address=get_client_ip(request),
        user_agent=request.headers.get("user-agent"),
    )

    return MessageResponse(message="2FA desactive")


# ---------------------------------------------------------------------------
# POST /enable-2fa-email
# ---------------------------------------------------------------------------
@router.post("/enable-2fa-email", response_model=MessageResponse)
def enable_two_factor_email(
    request: Request,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Initie l'activation de la 2FA par email : envoie un code de verification."""
    if current_user.is_2fa_enabled:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="2FA deja active",
        )
    try:
        enable_2fa_email(db, current_user)
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Erreur lors de l'envoi du code : {e}",
        )

    log_audit(
        db, user_id=current_user.id, action="2FA_EMAIL_INITIATED",
        resource_type="AUTH",
        ip_address=get_client_ip(request),
        user_agent=request.headers.get("user-agent"),
    )

    return MessageResponse(message="Code de verification envoye par email")


# ---------------------------------------------------------------------------
# POST /verify-2fa-email
# ---------------------------------------------------------------------------
@router.post("/verify-2fa-email", response_model=MessageResponse)
def verify_two_factor_email(
    body: Verify2FARequest,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Verifie le code email OTP et active definitivement la 2FA par email."""
    try:
        success = verify_and_activate_2fa_email(db, current_user, body.totp_code)
    except AuthError as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e),
        )
    if not success:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Code invalide",
        )

    log_audit(
        db, user_id=current_user.id, action="2FA_ENABLED",
        resource_type="AUTH",
        ip_address=get_client_ip(request),
        user_agent=request.headers.get("user-agent"),
        details={"method": "EMAIL"},
    )

    return MessageResponse(message="2FA par email activee avec succes")


# ---------------------------------------------------------------------------
# POST /resend-2fa-code
# ---------------------------------------------------------------------------
@router.post("/resend-2fa-code", response_model=MessageResponse)
def resend_two_factor_code(
    request: Request,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Renvoie un nouveau code OTP par email (pour configuration ou login)."""
    try:
        send_email_otp(db, current_user)
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Erreur lors de l'envoi du code : {e}",
        )
    return MessageResponse(message="Nouveau code envoye")


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
    _ip = get_client_ip(request)
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


# ---------------------------------------------------------------------------
# POST /forgot-password
# ---------------------------------------------------------------------------
@router.post("/forgot-password", response_model=MessageResponse)
def forgot_password(body: ForgotPasswordRequest, request: Request, db: Session = Depends(get_db)):
    """Envoie un email de reinitialisation si le compte existe (public)."""
    _ip = get_client_ip(request)
    _ua = request.headers.get("user-agent")

    base_url = str(request.headers.get("origin", "http://localhost:5173"))

    try:
        user = request_password_reset(db, body.email, base_url)
    except AuthError as e:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(e))
    except Exception:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Erreur lors de l'envoi de l'email. Veuillez reessayer.",
        )

    log_audit(
        db, user_id=user.id, action="PASSWORD_RESET_REQUESTED",
        resource_type="AUTH", ip_address=_ip, user_agent=_ua,
        details={"email": body.email},
    )

    return MessageResponse(
        message="Un lien de reinitialisation a ete envoye a votre adresse email."
    )


# ---------------------------------------------------------------------------
# POST /reset-password
# ---------------------------------------------------------------------------
@router.post("/reset-password", response_model=MessageResponse)
def reset_password(body: ResetPasswordRequest, request: Request, db: Session = Depends(get_db)):
    """Reinitialise le mot de passe avec un token valide (public)."""
    _ip = get_client_ip(request)
    _ua = request.headers.get("user-agent")

    try:
        user = reset_password_with_token(db, body.token, body.email, hash_password(body.new_password))
    except AuthError as e:
        log_audit(
            db, user_id=None, action="PASSWORD_RESET_FAILED",
            resource_type="AUTH", ip_address=_ip, user_agent=_ua,
            details={"email": body.email},
        )
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))

    log_audit(
        db, user_id=user.id, action="PASSWORD_RESET_SUCCESS",
        resource_type="AUTH", ip_address=_ip, user_agent=_ua,
        details={"email": body.email},
    )

    return MessageResponse(message="Mot de passe reinitialise avec succes")
