"""
Tests unitaires pour le service de chiffrement AES-256-GCM (US 6.3).
"""

import pytest
from app.services.crypto_service import decrypt_field, encrypt_field, EncryptedString


# ---------------------------------------------------------------------------
# encrypt_field / decrypt_field
# ---------------------------------------------------------------------------

class TestEncryptDecrypt:
    def test_roundtrip_simple(self):
        """Chiffrement puis dechiffrement retourne la valeur originale."""
        plaintext = "Jean-Pierre"
        ciphertext = encrypt_field(plaintext)
        assert ciphertext != plaintext
        assert decrypt_field(ciphertext) == plaintext

    def test_roundtrip_unicode(self):
        """Caracteres speciaux et accents sont preserves."""
        plaintext = "Marie-Helene Decrouez"
        assert decrypt_field(encrypt_field(plaintext)) == plaintext

    def test_roundtrip_empty_string(self):
        """Une chaine vide est chiffree et dechiffree correctement."""
        assert decrypt_field(encrypt_field("")) == ""

    def test_roundtrip_long_string(self):
        """Les chaines longues (> 255 chars) sont gerees."""
        plaintext = "A" * 500
        assert decrypt_field(encrypt_field(plaintext)) == plaintext

    def test_ciphertext_differs_each_time(self):
        """Deux chiffrements du meme texte produisent des resultats differents (nonce aleatoire)."""
        plaintext = "TestNonce"
        c1 = encrypt_field(plaintext)
        c2 = encrypt_field(plaintext)
        assert c1 != c2  # nonces differents
        assert decrypt_field(c1) == decrypt_field(c2) == plaintext

    def test_ciphertext_is_base64(self):
        """Le texte chiffre est du base64 valide."""
        import base64
        ciphertext = encrypt_field("Test")
        raw = base64.b64decode(ciphertext)
        assert len(raw) > 12  # nonce (12) + ciphertext + tag (16)

    def test_decrypt_invalid_raises(self):
        """Dechiffrer des donnees invalides leve une exception."""
        with pytest.raises(Exception):
            decrypt_field("not-valid-base64-encrypted-data!!!")

    def test_decrypt_tampered_data_raises(self):
        """Un texte chiffre altere est detecte (integrite GCM)."""
        import base64
        ciphertext = encrypt_field("Original")
        raw = bytearray(base64.b64decode(ciphertext))
        raw[-1] ^= 0xFF  # alterer le tag
        tampered = base64.b64encode(bytes(raw)).decode("ascii")
        with pytest.raises(Exception):
            decrypt_field(tampered)


# ---------------------------------------------------------------------------
# EncryptedString TypeDecorator
# ---------------------------------------------------------------------------

class TestEncryptedStringType:
    def setup_method(self):
        self.col_type = EncryptedString()

    def test_bind_param_encrypts(self):
        """process_bind_param chiffre la valeur."""
        result = self.col_type.process_bind_param("Jean", dialect=None)
        assert result != "Jean"
        assert decrypt_field(result) == "Jean"

    def test_bind_param_none_passthrough(self):
        """None n'est pas chiffre."""
        assert self.col_type.process_bind_param(None, dialect=None) is None

    def test_result_value_decrypts(self):
        """process_result_value dechiffre la valeur."""
        encrypted = encrypt_field("Marie")
        result = self.col_type.process_result_value(encrypted, dialect=None)
        assert result == "Marie"

    def test_result_value_none_passthrough(self):
        """None n'est pas dechiffre."""
        assert self.col_type.process_result_value(None, dialect=None) is None

    def test_result_value_plaintext_fallback(self):
        """Donnee non chiffree (migration) retournee telle quelle."""
        result = self.col_type.process_result_value("DonneeEnClair", dialect=None)
        assert result == "DonneeEnClair"

    def test_result_value_fallback_accented(self):
        """Donnee non chiffree avec accents retournee telle quelle."""
        result = self.col_type.process_result_value("Helene", dialect=None)
        assert result == "Helene"
