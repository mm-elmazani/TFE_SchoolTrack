"""Création d'une école de démonstration avec 3 comptes de base.

Idempotent : peut être relancé sans créer de doublons.
À exécuter dans le conteneur backend :

    docker exec schooltrack_api python scripts/create_demo_school.py

Mot de passe par défaut pour les 3 comptes : Demo123!
"""

import sys

# /app est le WORKDIR du conteneur backend (cf. Dockerfile)
sys.path.insert(0, "/app")

from app.database import SessionLocal
from app.models.school import School
from app.models.user import User
from app.services.auth_service import hash_password


DEMO_SLUG = "demo"
DEMO_NAME = "École de démonstration"
DEFAULT_PASSWORD = "Demo123!"

USERS = [
    # (email, role, first_name, last_name)
    ("direction@demo.schooltrack.be", "DIRECTION",  "Direction",  "Démo"),
    ("teacher@demo.schooltrack.be",   "TEACHER",    "Enseignant", "Démo"),
    ("admin@demo.schooltrack.be",     "ADMIN_TECH", "Admin",      "Tech"),
]


def main() -> int:
    db = SessionLocal()
    try:
        # 1) École
        school = db.query(School).filter_by(slug=DEMO_SLUG).first()
        if school is not None:
            print(f"[=] École '{DEMO_SLUG}' déjà présente — id={school.id}")
        else:
            school = School(name=DEMO_NAME, slug=DEMO_SLUG, is_active=True)
            db.add(school)
            db.flush()  # pour récupérer school.id sans commit
            print(f"[+] École '{DEMO_SLUG}' créée — id={school.id}")

        # 2) Comptes utilisateurs
        password_hash = hash_password(DEFAULT_PASSWORD)
        for email, role, first_name, last_name in USERS:
            existing = db.query(User).filter_by(email=email).first()
            if existing is not None:
                tag = "même école" if existing.school_id == school.id else f"AUTRE école {existing.school_id}"
                print(f"[=] {email} ({role}) déjà présent — {tag}")
                continue
            user = User(
                email=email,
                password_hash=password_hash,
                role=role,
                first_name=first_name,
                last_name=last_name,
                school_id=school.id,
                is_2fa_enabled=False,
            )
            db.add(user)
            print(f"[+] {email} ({role}) créé")

        db.commit()
        print(f"\nTerminé. École '{DEMO_SLUG}' prête. Mot de passe partagé : {DEFAULT_PASSWORD}")
        return 0
    except Exception as exc:
        db.rollback()
        print(f"\nErreur (rollback effectué) : {exc}", file=sys.stderr)
        return 1
    finally:
        db.close()


if __name__ == "__main__":
    sys.exit(main())
