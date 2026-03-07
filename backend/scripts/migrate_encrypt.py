"""
Script de migration -- Chiffrement AES-256-GCM des colonnes PII (US 6.3).

1. ALTER TABLE : VARCHAR -> TEXT pour les colonnes chiffrees
2. Chiffre les donnees existantes en place (students + users)

Usage : python -m scripts.migrate_encrypt
Executer depuis le dossier backend/ avec la BDD accessible.
"""

import sys
import os

# Ajouter le dossier parent au path pour importer app.*
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from sqlalchemy import text
from app.database import engine
from app.services.crypto_service import encrypt_field


def run_migration():
    print("=== Migration US 6.3 -- Chiffrement des donnees sensibles ===\n")

    with engine.connect() as conn:
        # Etape 1 : ALTER TABLE -- VARCHAR -> TEXT
        print("[1/3] ALTER TABLE -- colonnes VARCHAR -> TEXT...")
        alter_statements = [
            "ALTER TABLE students ALTER COLUMN first_name TYPE TEXT",
            "ALTER TABLE students ALTER COLUMN last_name TYPE TEXT",
            "ALTER TABLE students ALTER COLUMN email TYPE TEXT",
            "ALTER TABLE users ALTER COLUMN first_name TYPE TEXT",
            "ALTER TABLE users ALTER COLUMN last_name TYPE TEXT",
            "ALTER TABLE users ALTER COLUMN totp_secret TYPE TEXT",
        ]
        for stmt in alter_statements:
            try:
                conn.execute(text(stmt))
            except Exception as e:
                print(f"  (deja TEXT ou erreur ignoree : {e})")
        conn.commit()
        print("  OK\n")

        # Etape 2 : Chiffrer les donnees students
        print("[2/3] Chiffrement des donnees students...")
        rows = conn.execute(text("SELECT id, first_name, last_name, email FROM students")).fetchall()
        count = 0
        for row in rows:
            sid, fn, ln, em = row
            try:
                # Verifier si deja chiffre (tentative de dechiffrement)
                from app.services.crypto_service import decrypt_field
                decrypt_field(fn)
                continue  # Deja chiffre, passer
            except Exception:
                pass  # Pas chiffre, on continue

            enc_fn = encrypt_field(fn) if fn else None
            enc_ln = encrypt_field(ln) if ln else None
            enc_em = encrypt_field(em) if em else None
            conn.execute(
                text("UPDATE students SET first_name = :fn, last_name = :ln, email = :em WHERE id = :id"),
                {"fn": enc_fn, "ln": enc_ln, "em": enc_em, "id": sid},
            )
            count += 1
        conn.commit()
        print(f"  {count} eleve(s) chiffre(s)\n")

        # Etape 3 : Chiffrer les donnees users (first_name, last_name, totp_secret)
        print("[3/3] Chiffrement des donnees users...")
        rows = conn.execute(
            text("SELECT id, first_name, last_name, totp_secret FROM users")
        ).fetchall()
        count = 0
        for row in rows:
            uid, fn, ln, ts = row
            try:
                if fn:
                    decrypt_field(fn)
                    continue  # Deja chiffre
            except Exception:
                pass

            enc_fn = encrypt_field(fn) if fn else None
            enc_ln = encrypt_field(ln) if ln else None
            enc_ts = encrypt_field(ts) if ts else None
            conn.execute(
                text(
                    "UPDATE users SET first_name = :fn, last_name = :ln, totp_secret = :ts WHERE id = :id"
                ),
                {"fn": enc_fn, "ln": enc_ln, "ts": enc_ts, "id": uid},
            )
            count += 1
        conn.commit()
        print(f"  {count} utilisateur(s) chiffre(s)\n")

    print("=== Migration terminee avec succes ===")


if __name__ == "__main__":
    run_migration()
