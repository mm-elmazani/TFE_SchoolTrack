"""
Service d'authentification (US 6.1).
Hachage bcrypt, JWT access/refresh, verrouillage de compte, TOTP 2FA.
"""

from datetime import datetime, timedelta, timezone

import bcrypt
import pyotp
from jose import JWTError, jwt
from sqlalchemy.orm import Session

from app.config import settings
from app.models.user import User

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
            raise TwoFactorRequiredError("Code 2FA requis")
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
    """Active le 2FA pour un utilisateur. Retourne (secret, provisioning_uri)."""
    secret, uri = generate_totp_secret(user)
    user.totp_secret = secret
    # Ne pas encore mettre is_2fa_enabled=True : attendre la verification
    db.commit()
    return secret, uri


def verify_and_activate_2fa(db: Session, user: User, totp_code: str) -> bool:
    """Verifie le code TOTP et active definitivement le 2FA."""
    if not user.totp_secret:
        raise AuthError("2FA non initialisee. Appelez d'abord enable-2fa.")
    totp = pyotp.TOTP(user.totp_secret)
    if not totp.verify(totp_code, valid_window=1):
        return False
    user.is_2fa_enabled = True
    db.commit()
    return True


def disable_2fa(db: Session, user: User) -> None:
    """Desactive le 2FA pour un utilisateur."""
    user.totp_secret = None
    user.is_2fa_enabled = False
    db.commit()


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
