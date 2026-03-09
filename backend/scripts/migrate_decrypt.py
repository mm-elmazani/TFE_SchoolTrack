"""
Script de migration -- Dechiffrement des colonnes PII (US 6.3).

Inverse de migrate_encrypt.py : dechiffre toutes les colonnes chiffrees
pour permettre une rotation de cle ENCRYPTION_KEY.

Workflow de rotation :
1. python -m scripts.migrate_decrypt   (avec l'ancienne cle)
2. Mettre a jour ENCRYPTION_KEY dans .env
3. python -m scripts.migrate_encrypt   (avec la nouvelle cle)

Usage : python -m scripts.migrate_decrypt
Executer depuis le dossier backend/ avec la BDD accessible.
"""

import sys
import os

# Ajouter le dossier parent au path pour importer app.*
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from sqlalchemy import text
from app.database import engine
from app.services.crypto_service import decrypt_field


def run_migration():
    print("=== Migration US 6.3 -- Dechiffrement des donnees sensibles ===\n")

    with engine.connect() as conn:
        # Etape 1 : Dechiffrer les donnees students
        print("[1/2] Dechiffrement des donnees students...")
        rows = conn.execute(text("SELECT id, first_name, last_name, email FROM students")).fetchall()
        count = 0
        for row in rows:
            sid, fn, ln, em = row

            # Verifier si la donnee est chiffree (base64 long = chiffre, texte court = clair)
            try:
                dec_fn = decrypt_field(fn) if fn else None
            except Exception:
                # Pas chiffre ou deja en clair, passer
                continue

            dec_ln = decrypt_field(ln) if ln else None
            dec_em = decrypt_field(em) if em else None

            conn.execute(
                text("UPDATE students SET first_name = :fn, last_name = :ln, email = :em WHERE id = :id"),
                {"fn": dec_fn, "ln": dec_ln, "em": dec_em, "id": sid},
            )
            count += 1
        conn.commit()
        print(f"  {count} eleve(s) dechiffre(s)\n")

        # Etape 2 : Dechiffrer les donnees users (first_name, last_name, totp_secret)
        print("[2/2] Dechiffrement des donnees users...")
        rows = conn.execute(
            text("SELECT id, first_name, last_name, totp_secret FROM users")
        ).fetchall()
        count = 0
        for row in rows:
            uid, fn, ln, ts = row

            try:
                dec_fn = decrypt_field(fn) if fn else None
            except Exception:
                continue

            dec_ln = decrypt_field(ln) if ln else None
            dec_ts = decrypt_field(ts) if ts else None

            conn.execute(
                text(
                    "UPDATE users SET first_name = :fn, last_name = :ln, totp_secret = :ts WHERE id = :id"
                ),
                {"fn": dec_fn, "ln": dec_ln, "ts": dec_ts, "id": uid},
            )
            count += 1
        conn.commit()
        print(f"  {count} utilisateur(s) dechiffre(s)\n")

    print("=== Dechiffrement termine avec succes ===")
    print("Vous pouvez maintenant mettre a jour ENCRYPTION_KEY dans .env")
    print("puis executer : python -m scripts.migrate_encrypt")


if __name__ == "__main__":
    run_migration()
