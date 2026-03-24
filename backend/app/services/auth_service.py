"""
Service d'authentification (US 6.1).
Hachage bcrypt, JWT access/refresh, verrouillage de compte, TOTP 2FA, Email OTP.
"""

import logging
import secrets
import smtplib
from datetime import datetime, timedelta, timezone
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText

import bcrypt
import pyotp
from jose import JWTError, jwt
from sqlalchemy.orm import Session

from app.config import settings
from app.models.user import User

logger = logging.getLogger(__name__)

EMAIL_OTP_EXPIRY_MINUTES = 10

MAX_FAILED_ATTEMPTS = 5
LOCKOUT_DURATION_MINUTES = 15


# ---------------------------------------------------------------------------
# Hachage — bcrypt direct (cout 12, critere US 6.1)
# ---------------------------------------------------------------------------

def hash_password(password: str) -> str:
    salt = bcrypt.gensalt(rounds=12)
    return bcrypt.hashpw(password.encode("utf-8"), salt).decode("utf-8")


def verify_password(plain_password: str, hashed_password: str) -> bool:
    return bcrypt.checkpw(
        plain_password.encode("utf-8"),
        hashed_password.encode("utf-8"),
    )


# ---------------------------------------------------------------------------
# JWT
# ---------------------------------------------------------------------------

def create_access_token(user: User) -> str:
    expire = datetime.now(timezone.utc) + timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)
    payload = {
        "sub": str(user.id),
        "email": user.email,
        "role": user.role,
        "type": "access",
        "exp": expire,
    }
    return jwt.encode(payload, settings.SECRET_KEY, algorithm=settings.ALGORITHM)


def create_refresh_token(user: User) -> str:
    expire = datetime.now(timezone.utc) + timedelta(minutes=settings.REFRESH_TOKEN_EXPIRE_MINUTES)
    payload = {
        "sub": str(user.id),
        "type": "refresh",
        "exp": expire,
    }
    return jwt.encode(payload, settings.SECRET_KEY, algorithm=settings.ALGORITHM)


def decode_token(token: str) -> dict:
    """Decode un JWT et retourne le payload. Leve JWTError si invalide/expire."""
    return jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])


# ---------------------------------------------------------------------------
# Authentification
# ---------------------------------------------------------------------------

def authenticate_user(
    db: Session,
    email: str,
    password: str,
    totp_code: str | None = None,
) -> User:
    """
    Authentifie un utilisateur par email + mot de passe (+ TOTP optionnel).
    Gere le verrouillage apres 5 tentatives echouees pendant 15 minutes.
    """
    user = db.query(User).filter(User.email == email).first()
    if not user:
        raise AuthError("Identifiants invalides")

    # Verifier le verrouillage
    now = datetime.utcnow()
    if user.locked_until and user.locked_until > now:
        remaining = int((user.locked_until - now).total_seconds() // 60) + 1
        raise AccountLockedError(
            f"Compte verrouille. Reessayez dans {remaining} minute(s)."
        )

    # Verifier le mot de passe
    if not verify_password(password, user.password_hash):
        user.failed_attempts = (user.failed_attempts or 0) + 1
        if user.failed_attempts >= MAX_FAILED_ATTEMPTS:
            user.locked_until = datetime.utcnow() + timedelta(minutes=LOCKOUT_DURATION_MINUTES)
        db.commit()
        raise AuthError("Identifiants invalides")

    # Verifier 2FA si active
    if user.is_2fa_enabled:
        if not totp_code:
            # Pour la methode EMAIL, envoyer un code avant de lever l'erreur
            if user.two_fa_method == "EMAIL":
                send_email_otp(db, user)
                raise TwoFactorRequiredError("2FA_REQUIRED_EMAIL")
            raise TwoFactorRequiredError("2FA_REQUIRED")
        # Verification selon la methode
        if user.two_fa_method == "EMAIL":
            if not verify_email_otp(db, user, totp_code):
                raise AuthError("Code 2FA invalide ou expire")
        else:
            totp = pyotp.TOTP(user.totp_secret)
            if not totp.verify(totp_code, valid_window=1):
                raise AuthError("Code 2FA invalide")

    # Succes : reset compteur + mise a jour last_login
    user.failed_attempts = 0
    user.locked_until = None
    user.last_login = datetime.utcnow()
    db.commit()
    db.refresh(user)

    return user


def register_user(
    db: Session,
    email: str,
    password_hash: str,
    first_name: str | None,
    last_name: str | None,
    role: str,
) -> User:
    """Cree un nouvel utilisateur en base."""
    user = User(
        email=email,
        password_hash=password_hash,
        first_name=first_name,
        last_name=last_name,
        role=role,
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return user


def refresh_access_token(db: Session, refresh_token: str) -> User:
    """Valide un refresh token et retourne l'utilisateur associe."""
    try:
        payload = decode_token(refresh_token)
    except JWTError:
        raise AuthError("Refresh token invalide ou expire")

    if payload.get("type") != "refresh":
        raise AuthError("Token invalide (type attendu: refresh)")

    user_id = payload.get("sub")
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise AuthError("Utilisateur introuvable")

    return user


# ---------------------------------------------------------------------------
# 2FA TOTP
# ---------------------------------------------------------------------------

def generate_totp_secret(user: User) -> tuple[str, str]:
    """Genere un secret TOTP et retourne (secret, provisioning_uri)."""
    secret = pyotp.random_base32()
    totp = pyotp.TOTP(secret)
    uri = totp.provisioning_uri(name=user.email, issuer_name="SchoolTrack")
    return secret, uri


def enable_2fa(db: Session, user: User) -> tuple[str, str]:
    """Active le 2FA (methode APP) pour un utilisateur. Retourne (secret, provisioning_uri)."""
    secret, uri = generate_totp_secret(user)
    user.totp_secret = secret
    user.two_fa_method = "APP"
    # Ne pas encore mettre is_2fa_enabled=True : attendre la verification
    db.commit()
    return secret, uri


def verify_and_activate_2fa(db: Session, user: User, totp_code: str) -> bool:
    """Verifie le code TOTP et active definitivement le 2FA (methode APP)."""
    if not user.totp_secret:
        raise AuthError("2FA non initialisee. Appelez d'abord enable-2fa.")
    totp = pyotp.TOTP(user.totp_secret)
    if not totp.verify(totp_code, valid_window=1):
        return False
    user.is_2fa_enabled = True
    user.two_fa_method = "APP"
    db.commit()
    return True


def disable_2fa(db: Session, user: User) -> None:
    """Desactive le 2FA pour un utilisateur."""
    user.totp_secret = None
    user.is_2fa_enabled = False
    user.two_fa_method = None
    user.email_otp_code = None
    user.email_otp_expires = None
    db.commit()


# ---------------------------------------------------------------------------
# 2FA Email OTP
# ---------------------------------------------------------------------------

def _generate_otp_code() -> str:
    """Genere un code OTP a 6 chiffres."""
    return f"{secrets.randbelow(1_000_000):06d}"


def _send_otp_email(to_email: str, code: str) -> None:
    """Envoie un email contenant le code OTP 2FA."""
    msg = MIMEMultipart("alternative")
    msg["From"] = settings.SMTP_FROM
    msg["To"] = to_email
    msg["Subject"] = f"SchoolTrack — Votre code de verification : {code}"

    html = f"""
    <html>
      <body style="font-family: Arial, sans-serif; color: #333; max-width: 600px; margin: auto;">
        <h2 style="color: #1a73e8;">SchoolTrack — Code de verification</h2>
        <p>Voici votre code de verification :</p>
        <div style="text-align: center; margin: 24px 0;">
          <span style="font-size: 32px; font-weight: bold; letter-spacing: 8px;
                       background: #f1f5f9; padding: 16px 32px; border-radius: 12px;
                       display: inline-block; color: #1a73e8;">{code}</span>
        </div>
        <p>Ce code expire dans <strong>{EMAIL_OTP_EXPIRY_MINUTES} minutes</strong>.</p>
        <p>Si vous n'avez pas demande ce code, ignorez cet email.</p>
        <hr style="border: none; border-top: 1px solid #eee;" />
        <p style="font-size: 12px; color: #888;">
          Ce message est genere automatiquement par SchoolTrack.
        </p>
      </body>
    </html>
    """
    msg.attach(MIMEText(html, "html", "utf-8"))

    with smtplib.SMTP(settings.SMTP_HOST, settings.SMTP_PORT) as server:
        if settings.SMTP_USE_TLS:
            server.starttls()
        if settings.SMTP_USERNAME:
            server.login(settings.SMTP_USERNAME, settings.SMTP_PASSWORD)
        server.send_message(msg)

    logger.info("Code OTP 2FA envoye a %s", to_email)


def send_email_otp(db: Session, user: User) -> None:
    """Genere un code OTP, le stocke en base et l'envoie par email."""
    code = _generate_otp_code()
    user.email_otp_code = code
    user.email_otp_expires = datetime.utcnow() + timedelta(minutes=EMAIL_OTP_EXPIRY_MINUTES)
    db.commit()
    _send_otp_email(user.email, code)


def enable_2fa_email(db: Session, user: User) -> None:
    """Initie l'activation de la 2FA par email : envoie un code de verification."""
    user.two_fa_method = "EMAIL"
    db.commit()
    send_email_otp(db, user)


def verify_and_activate_2fa_email(db: Session, user: User, code: str) -> bool:
    """Verifie le code email OTP et active definitivement la 2FA (methode EMAIL)."""
    if not user.email_otp_code or not user.email_otp_expires:
        raise AuthError("Aucun code OTP en attente. Appelez d'abord enable-2fa-email.")
    if datetime.utcnow() > user.email_otp_expires:
        user.email_otp_code = None
        user.email_otp_expires = None
        db.commit()
        raise AuthError("Code OTP expire. Demandez un nouveau code.")
    if user.email_otp_code != code:
        return False
    user.is_2fa_enabled = True
    user.two_fa_method = "EMAIL"
    user.email_otp_code = None
    user.email_otp_expires = None
    db.commit()
    return True


def verify_email_otp(db: Session, user: User, code: str) -> bool:
    """Verifie un code email OTP (utilise au login). Retourne True si valide."""
    if not user.email_otp_code or not user.email_otp_expires:
        return False
    if datetime.utcnow() > user.email_otp_expires:
        user.email_otp_code = None
        user.email_otp_expires = None
        db.commit()
        return False
    if user.email_otp_code != code:
        return False
    # Code valide — nettoyer
    user.email_otp_code = None
    user.email_otp_expires = None
    db.commit()
    return True


# ---------------------------------------------------------------------------
# Changement de mot de passe
# ---------------------------------------------------------------------------

def change_password(db: Session, user: User, current_password: str, new_password_hash: str) -> None:
    """Change le mot de passe apres verification de l'ancien."""
    if not verify_password(current_password, user.password_hash):
        raise AuthError("Mot de passe actuel incorrect")
    user.password_hash = new_password_hash
    user.failed_attempts = 0
    user.locked_until = None
    db.commit()


# ---------------------------------------------------------------------------
# Exceptions
# ---------------------------------------------------------------------------

class AuthError(Exception):
    """Erreur d'authentification generique."""
    pass


class AccountLockedError(Exception):
    """Compte verrouille apres trop de tentatives."""
    pass


class TwoFactorRequiredError(Exception):
    """Le 2FA est active mais aucun code TOTP n'a ete fourni."""
    pass
