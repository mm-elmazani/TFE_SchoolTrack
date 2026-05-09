"""
Service d'authentification.
Hachage bcrypt, JWT access/refresh, verrouillage de compte, TOTP 2FA, Email OTP.
"""

import logging
import secrets
import smtplib
from datetime import datetime, timedelta, timezone
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from urllib.parse import quote

import bcrypt
import pyotp
from jose import JWTError, jwt
from sqlalchemy.orm import Session

from app.config import settings
from app.models.user import User

logger = logging.getLogger(__name__)

EMAIL_OTP_EXPIRY_MINUTES = 10
PASSWORD_RESET_EXPIRY_MINUTES = settings.PASSWORD_RESET_TOKEN_EXPIRE_MINUTES

MAX_FAILED_ATTEMPTS = 5
LOCKOUT_DURATION_MINUTES = 15


def hash_password(password: str) -> str:
    salt = bcrypt.gensalt(rounds=12)
    return bcrypt.hashpw(password.encode("utf-8"), salt).decode("utf-8")


def verify_password(plain_password: str, hashed_password: str) -> bool:
    return bcrypt.checkpw(
        plain_password.encode("utf-8"),
        hashed_password.encode("utf-8"),
    )


def create_access_token(user: User) -> str:
    expire = datetime.now(timezone.utc) + timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)
    payload = {
        "sub": str(user.id),
        "email": user.email,
        "role": user.role,
        "school_id": str(user.school_id),
        "type": "access",
        "exp": expire,
    }
    return jwt.encode(payload, settings.SECRET_KEY, algorithm=settings.ALGORITHM)


def create_refresh_token(user: User, extended: bool = False) -> str:
    """Genere un refresh token JWT.

    Si `extended=True`, la duree de vie est etendue (case "rester connecte"
    cochee cote client) — typiquement 7 jours au lieu de 24h.
    """
    minutes = (
        settings.EXTENDED_REFRESH_TOKEN_EXPIRE_MINUTES
        if extended
        else settings.REFRESH_TOKEN_EXPIRE_MINUTES
    )
    expire = datetime.now(timezone.utc) + timedelta(minutes=minutes)
    payload = {
        "sub": str(user.id),
        "type": "refresh",
        "extended": extended,
        "exp": expire,
    }
    return jwt.encode(payload, settings.SECRET_KEY, algorithm=settings.ALGORITHM)


def decode_token(token: str) -> dict:
    return jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])


def authenticate_user(
    db: Session,
    email: str,
    password: str,
    totp_code: str | None = None,
) -> User:
    """
    Authentifie un utilisateur par email + mot de passe (TOTP optionnel).
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
    school_id=None,
) -> User:
    user = User(
        email=email,
        password_hash=password_hash,
        first_name=first_name,
        last_name=last_name,
        role=role,
        school_id=school_id,
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return user


def refresh_access_token(db: Session, refresh_token: str) -> tuple[User, bool]:
    """Valide un refresh token et retourne (user, extended_flag).

    Le flag `extended` est propage du refresh token consomme — ainsi un
    utilisateur ayant coche "rester connecte" garde sa session longue
    a chaque refresh.
    """
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

    extended = bool(payload.get("extended", False))
    return user, extended


def generate_totp_secret(user: User) -> tuple[str, str]:
    secret = pyotp.random_base32()
    totp = pyotp.TOTP(secret)
    uri = totp.provisioning_uri(name=user.email, issuer_name="SchoolTrack")
    return secret, uri


def enable_2fa(db: Session, user: User) -> tuple[str, str]:
    secret, uri = generate_totp_secret(user)
    user.totp_secret = secret
    user.two_fa_method = "APP"
    # Ne pas encore mettre is_2fa_enabled=True : attendre la verification
    db.commit()
    return secret, uri


def verify_and_activate_2fa(db: Session, user: User, totp_code: str) -> bool:
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
    user.totp_secret = None
    user.is_2fa_enabled = False
    user.two_fa_method = None
    user.email_otp_code = None
    user.email_otp_expires = None
    db.commit()


def _generate_otp_code() -> str:
    return f"{secrets.randbelow(1_000_000):06d}"


def _send_otp_email(to_email: str, code: str) -> None:
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

    with smtplib.SMTP(settings.SMTP_HOST, settings.SMTP_PORT, timeout=30) as server:
        server.ehlo()
        if settings.SMTP_USE_TLS:
            server.starttls()
            server.ehlo()
        if settings.SMTP_USERNAME:
            server.login(settings.SMTP_USERNAME, settings.SMTP_PASSWORD)
        server.send_message(msg)

    logger.info("Code OTP 2FA envoye a %s", to_email)


def send_email_otp(db: Session, user: User) -> None:
    code = _generate_otp_code()
    user.email_otp_code = code
    user.email_otp_expires = datetime.utcnow() + timedelta(minutes=EMAIL_OTP_EXPIRY_MINUTES)
    db.commit()
    _send_otp_email(user.email, code)


def enable_2fa_email(db: Session, user: User) -> None:
    user.two_fa_method = "EMAIL"
    db.commit()
    send_email_otp(db, user)


def verify_and_activate_2fa_email(db: Session, user: User, code: str) -> bool:
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


def change_password(db: Session, user: User, current_password: str, new_password_hash: str) -> None:
    if not verify_password(current_password, user.password_hash):
        raise AuthError("Mot de passe actuel incorrect")
    user.password_hash = new_password_hash
    user.failed_attempts = 0
    user.locked_until = None
    db.commit()


def _generate_reset_token() -> str:
    return secrets.token_urlsafe(32)


def _send_password_reset_email(to_email: str, reset_url: str) -> None:
    msg = MIMEMultipart("alternative")
    msg["From"] = settings.SMTP_FROM
    msg["To"] = to_email
    msg["Subject"] = "SchoolTrack — Reinitialisation de votre mot de passe"

    html = f"""
    <html>
      <body style="font-family: Arial, sans-serif; color: #333; max-width: 600px; margin: auto;">
        <h2 style="color: #005293;">SchoolTrack — Reinitialisation du mot de passe</h2>
        <p>Vous avez demande la reinitialisation de votre mot de passe.</p>
        <p>Cliquez sur le bouton ci-dessous pour definir un nouveau mot de passe :</p>
        <div style="text-align: center; margin: 32px 0;">
          <a href="{reset_url}"
             style="background: #005293; color: #fff; padding: 14px 32px; border-radius: 8px;
                    text-decoration: none; font-weight: bold; font-size: 16px;
                    display: inline-block;">
            Reinitialiser mon mot de passe
          </a>
        </div>
        <p>Ce lien expire dans <strong>{PASSWORD_RESET_EXPIRY_MINUTES} minutes</strong>.</p>
        <p>Si vous n'avez pas demande cette reinitialisation, ignorez cet email.
           Votre mot de passe restera inchange.</p>
        <hr style="border: none; border-top: 1px solid #eee;" />
        <p style="font-size: 12px; color: #888;">
          Ce message est genere automatiquement par SchoolTrack.
        </p>
      </body>
    </html>
    """
    msg.attach(MIMEText(html, "html", "utf-8"))

    with smtplib.SMTP(settings.SMTP_HOST, settings.SMTP_PORT, timeout=30) as server:
        server.ehlo()
        if settings.SMTP_USE_TLS:
            server.starttls()
            server.ehlo()
        if settings.SMTP_USERNAME:
            server.login(settings.SMTP_USERNAME, settings.SMTP_PASSWORD)
        server.send_message(msg)

    logger.info("Email de reinitialisation envoye a %s", to_email)


def request_password_reset(db: Session, email: str, base_url: str, school_slug: str | None = None) -> User:
    """
    Genere un token de reset et envoie l'email.
    Leve AuthError si l'email n'existe pas.
    Retourne l'utilisateur pour le logging.
    """
    user = db.query(User).filter(User.email == email).first()
    if not user:
        raise AuthError("Aucun compte associe a cet email")

    token = _generate_reset_token()
    user.password_reset_token = token
    user.password_reset_expires = datetime.utcnow() + timedelta(minutes=PASSWORD_RESET_EXPIRY_MINUTES)
    db.commit()

    # Inclure le school_slug dans l'URL pour correspondre aux routes React /:schoolSlug/reset-password
    # L'email est URL-encodé pour éviter les problèmes avec + et autres caractères spéciaux
    encoded_email = quote(email, safe='')
    if school_slug:
        reset_url = f"{base_url}/{school_slug}/reset-password?token={token}&email={encoded_email}"
    else:
        reset_url = f"{base_url}/reset-password?token={token}&email={encoded_email}"

    _send_password_reset_email(user.email, reset_url)
    return user


def reset_password_with_token(db: Session, token: str, email: str, new_password_hash: str) -> User:
    user = db.query(User).filter(User.email == email).first()
    if not user:
        raise AuthError("Lien de reinitialisation invalide")

    if not user.password_reset_token or user.password_reset_token != token:
        raise AuthError("Lien de reinitialisation invalide")

    if not user.password_reset_expires or datetime.utcnow() > user.password_reset_expires:
        user.password_reset_token = None
        user.password_reset_expires = None
        db.commit()
        raise AuthError("Le lien de reinitialisation a expire")

    user.password_hash = new_password_hash
    user.password_reset_token = None
    user.password_reset_expires = None
    user.failed_attempts = 0
    user.locked_until = None
    db.commit()
    return user


class AuthError(Exception):
    pass


class AccountLockedError(Exception):
    pass


class TwoFactorRequiredError(Exception):
    pass
