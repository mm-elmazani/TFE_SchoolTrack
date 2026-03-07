"""
Service de chiffrement des donnees sensibles (US 6.3).
AES-256-GCM pour le chiffrement au repos des colonnes PII (noms, prenoms, emails).
"""

import base64
import hashlib
import os

from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from sqlalchemy import Text
from sqlalchemy.types import TypeDecorator

from app.config import settings


def _get_key() -> bytes:
    """Derive une cle AES-256 (32 octets) depuis ENCRYPTION_KEY via SHA-256."""
    return hashlib.sha256(settings.ENCRYPTION_KEY.encode("utf-8")).digest()


def encrypt_field(value: str) -> str:
    """Chiffre une valeur avec AES-256-GCM. Retourne base64(nonce || ciphertext || tag)."""
    aesgcm = AESGCM(_get_key())
    nonce = os.urandom(12)  # 96 bits recommandes par NIST
    ciphertext = aesgcm.encrypt(nonce, value.encode("utf-8"), None)
    return base64.b64encode(nonce + ciphertext).decode("ascii")


def decrypt_field(value: str) -> str:
    """Dechiffre une valeur AES-256-GCM depuis base64(nonce || ciphertext || tag)."""
    raw = base64.b64decode(value)
    nonce, ciphertext = raw[:12], raw[12:]
    aesgcm = AESGCM(_get_key())
    return aesgcm.decrypt(nonce, ciphertext, None).decode("utf-8")


class EncryptedString(TypeDecorator):
    """
    Type SQLAlchemy qui chiffre/dechiffre de maniere transparente via AES-256-GCM.
    Stockage : TEXT chiffre en base64.  Acces Python : valeur en clair.
    Pendant la migration, les donnees non chiffrees sont retournees telles quelles.
    """
    impl = Text
    cache_ok = True

    def process_bind_param(self, value, dialect):
        """Chiffrement avant ecriture en base."""
        if value is not None:
            return encrypt_field(value)
        return value

    def process_result_value(self, value, dialect):
        """Dechiffrement apres lecture depuis la base."""
        if value is not None:
            try:
                return decrypt_field(value)
            except Exception:
                return value  # Donnee non encore chiffree (migration en cours)
        return value
