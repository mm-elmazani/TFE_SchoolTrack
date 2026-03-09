"""
Script de seed — Donnees de demonstration pour SchoolTrack.
Usage : cd backend && python ../demo/seed_demo.py

Cree des donnees realistes pour une demo :
- 2 classes (3TI-A, 3TI-B)
- 25 eleves repartis dans les 2 classes
- 1 voyage ACTIVE (demain) + 1 voyage PLANNED (semaine prochaine)
- 25 tokens NFC physiques
- Assignations bracelets pour le voyage actif
- 3 checkpoints + quelques presences scannees
"""

import os
import sys
import uuid
from datetime import date, datetime, timedelta
from pathlib import Path

# -- Setup path pour import depuis la racine backend/ -----------------------
# Ce script vit dans demo/ mais importe les modules de backend/app/
SCRIPT_DIR = Path(__file__).resolve().parent
BACKEND_DIR = SCRIPT_DIR.parent / "backend"
sys.path.insert(0, str(BACKEND_DIR))
os.chdir(BACKEND_DIR)  # pour que .env soit trouve par pydantic-settings

from app.database import SessionLocal, engine
from app.models import *  # noqa: F401,F403 — charge tous les modeles
from app.models.assignment import Assignment, Token
from app.models.attendance import Attendance
from app.models.checkpoint import Checkpoint
from app.models.school_class import ClassStudent, ClassTeacher, SchoolClass
from app.models.student import Student
from app.models.trip import Trip, TripStudent
from app.models.user import User
from app.services.auth_service import hash_password

# ===========================================================================
# DONNEES DE DEMO
# ===========================================================================

STUDENTS_3TI_A = [
    ("Lucas", "Dupont", "lucas.dupont@email.be"),
    ("Emma", "Martin", "emma.martin@email.be"),
    ("Noah", "Janssens", "noah.janssens@email.be"),
    ("Olivia", "Peeters", "olivia.peeters@email.be"),
    ("Louis", "Maes", "louis.maes@email.be"),
    ("Lina", "Claes", "lina.claes@email.be"),
    ("Arthur", "Jacobs", "arthur.jacobs@email.be"),
    ("Mila", "Mertens", "mila.mertens@email.be"),
    ("Adam", "Willems", "adam.willems@email.be"),
    ("Louise", "Goossens", "louise.goossens@email.be"),
    ("Victor", "Wouters", "victor.wouters@email.be"),
    ("Alice", "De Smedt", "alice.desmedt@email.be"),
    ("Jules", "Hermans", None),
]

STUDENTS_3TI_B = [
    ("Nathan", "Lambert", "nathan.lambert@email.be"),
    ("Camille", "Dubois", "camille.dubois@email.be"),
    ("Hugo", "Leroy", "hugo.leroy@email.be"),
    ("Clara", "Moreau", "clara.moreau@email.be"),
    ("Gabriel", "Simon", "gabriel.simon@email.be"),
    ("Jade", "Laurent", "jade.laurent@email.be"),
    ("Raphael", "Michel", "raphael.michel@email.be"),
    ("Lea", "Lefebvre", "lea.lefebvre@email.be"),
    ("Tom", "Roux", "tom.roux@email.be"),
    ("Sarah", "David", "sarah.david@email.be"),
    ("Maxime", "Bertrand", "maxime.bertrand@email.be"),
    ("Chloe", "Robert", None),
]


def seed():
    db = SessionLocal()
    try:
        # -- Verifier que la BDD n'est pas deja seedee -----------------------
        existing = db.query(Student).first()
        if existing:
            print("[!] Des donnees existent deja. Pour re-seeder :")
            print("    docker compose -f docker-compose.dev.yml down -v")
            print("    docker compose -f docker-compose.dev.yml up -d")
            print("    Attendre 5s puis relancer ce script.")
            return

        # -- Recuperer les users existants (crees par init.sql) ---------------
        admin = db.query(User).filter(User.email == "admin@schooltrack.be").first()
        teacher = db.query(User).filter(User.email == "teacher@schooltrack.be").first()

        if not admin or not teacher:
            print("[!] Users seed introuvables. Verifier que init.sql a ete execute.")
            return

        print(f"[OK] Admin  : {admin.email} (id={admin.id})")
        print(f"[OK] Teacher: {teacher.email} (id={teacher.id})")

        # -- Creer un 2e enseignant -------------------------------------------
        teacher2_hash = hash_password("Teacher123!")
        teacher2 = User(
            email="marie.lejeune@schooltrack.be",
            password_hash=teacher2_hash,
            first_name="Marie",
            last_name="Lejeune",
            role="TEACHER",
            is_2fa_enabled=False,
        )
        db.add(teacher2)
        db.flush()
        print(f"[OK] Teacher 2 : {teacher2.email} / Teacher123!")

        # -- Creer un observateur ---------------------------------------------
        observer_hash = hash_password("Observer123!")
        observer = User(
            email="obs@schooltrack.be",
            password_hash=observer_hash,
            first_name="Pierre",
            last_name="Duval",
            role="OBSERVER",
            is_2fa_enabled=False,
        )
        db.add(observer)
        db.flush()
        print(f"[OK] Observer : {observer.email} / Observer123!")

        # -- Classes ----------------------------------------------------------
        class_a = SchoolClass(name="3TI-A", year="2025-2026")
        class_b = SchoolClass(name="3TI-B", year="2025-2026")
        db.add_all([class_a, class_b])
        db.flush()
        print(f"[OK] Classes : {class_a.name}, {class_b.name}")

        # -- Assigner enseignants aux classes ---------------------------------
        db.add(ClassTeacher(class_id=class_a.id, teacher_id=teacher.id))
        db.add(ClassTeacher(class_id=class_b.id, teacher_id=teacher2.id))
        db.flush()

        # -- Eleves 3TI-A ----------------------------------------------------
        students_a = []
        for first, last, email in STUDENTS_3TI_A:
            s = Student(first_name=first, last_name=last, email=email, parent_consent=True)
            db.add(s)
            students_a.append(s)
        db.flush()
        print(f"[OK] {len(students_a)} eleves crees pour {class_a.name}")

        for s in students_a:
            db.add(ClassStudent(class_id=class_a.id, student_id=s.id))
        db.flush()

        # -- Eleves 3TI-B ----------------------------------------------------
        students_b = []
        for first, last, email in STUDENTS_3TI_B:
            s = Student(first_name=first, last_name=last, email=email, parent_consent=True)
            db.add(s)
            students_b.append(s)
        db.flush()
        print(f"[OK] {len(students_b)} eleves crees pour {class_b.name}")

        for s in students_b:
            db.add(ClassStudent(class_id=class_b.id, student_id=s.id))
        db.flush()

        all_students = students_a + students_b

        # -- Tokens NFC -------------------------------------------------------
        tokens = []
        for i in range(1, 26):
            t = Token(
                token_uid=f"ST-{i:03d}",
                token_type="NFC_PHYSICAL",
                status="AVAILABLE",
            )
            db.add(t)
            tokens.append(t)
        db.flush()
        print(f"[OK] {len(tokens)} tokens NFC crees (ST-001 a ST-025)")

        # -- Voyage 1 : ACTIVE (demain) — les 2 classes ----------------------
        tomorrow = date.today() + timedelta(days=1)
        trip1 = Trip(
            destination="Bruxelles — Parlement Europeen",
            date=tomorrow,
            description="Visite guidee du Parlement europeen et du quartier des institutions. "
                        "Depart 8h00 devant l'ecole, retour prevu 17h00.",
            status="ACTIVE",
            created_by=admin.id,
        )
        db.add(trip1)
        db.flush()
        print(f"[OK] Voyage 1 : {trip1.destination} ({trip1.date}) — ACTIVE")

        # Inscrire tous les eleves au voyage 1
        for s in all_students:
            db.add(TripStudent(trip_id=trip1.id, student_id=s.id))
        db.flush()

        # Assigner des bracelets NFC a la classe A (13 eleves)
        for i, s in enumerate(students_a):
            a = Assignment(
                token_uid=f"ST-{i+1:03d}",
                student_id=s.id,
                trip_id=trip1.id,
                assignment_type="NFC_PHYSICAL",
                assigned_by=admin.id,
            )
            db.add(a)
            tokens[i].status = "ASSIGNED"
        db.flush()
        print(f"[OK] {len(students_a)} bracelets NFC assignes (3TI-A)")

        # Assigner des bracelets NFC a la classe B (12 eleves)
        for i, s in enumerate(students_b):
            idx = len(students_a) + i
            a = Assignment(
                token_uid=f"ST-{idx+1:03d}",
                student_id=s.id,
                trip_id=trip1.id,
                assignment_type="NFC_PHYSICAL",
                assigned_by=admin.id,
            )
            db.add(a)
            tokens[idx].status = "ASSIGNED"
        db.flush()
        print(f"[OK] {len(students_b)} bracelets NFC assignes (3TI-B)")

        # -- Checkpoints voyage 1 ---------------------------------------------
        cp1 = Checkpoint(
            trip_id=trip1.id,
            name="Depart ecole (comptage bus)",
            description="Verification des presences avant le depart du bus.",
            sequence_order=1,
            status="CLOSED",
            created_by=teacher.id,
            started_at=datetime.utcnow() - timedelta(hours=3),
            closed_at=datetime.utcnow() - timedelta(hours=2, minutes=45),
        )
        cp2 = Checkpoint(
            trip_id=trip1.id,
            name="Arrivee Parlement EU",
            description="Comptage a l'arrivee au Parlement europeen.",
            sequence_order=2,
            status="ACTIVE",
            created_by=teacher.id,
            started_at=datetime.utcnow() - timedelta(hours=1),
        )
        cp3 = Checkpoint(
            trip_id=trip1.id,
            name="Pause dejeuner — Parc du Cinquantenaire",
            sequence_order=3,
            status="DRAFT",
            created_by=teacher.id,
        )
        db.add_all([cp1, cp2, cp3])
        db.flush()
        print(f"[OK] 3 checkpoints crees pour voyage 1")

        # -- Presences checkpoint 1 (tous presents sauf 2) --------------------
        present_cp1 = all_students[:-2]  # 23 presents
        assignments_map = {}
        for a_record in db.query(Assignment).filter(
            Assignment.trip_id == trip1.id,
            Assignment.released_at.is_(None),
        ).all():
            assignments_map[str(a_record.student_id)] = a_record

        for idx, s in enumerate(present_cp1):
            a_rec = assignments_map.get(str(s.id))
            att = Attendance(
                client_uuid=uuid.uuid4(),
                trip_id=trip1.id,
                checkpoint_id=cp1.id,
                student_id=s.id,
                assignment_id=a_rec.id if a_rec else None,
                scanned_at=datetime.utcnow() - timedelta(hours=3) + timedelta(seconds=idx * 8),
                scanned_by=teacher.id,
                scan_method="NFC",
                scan_sequence=1,
            )
            db.add(att)
        db.flush()
        print(f"[OK] {len(present_cp1)} presences scannees au checkpoint 1")

        # -- Presences checkpoint 2 (18 presents pour l'instant) ---------------
        present_cp2 = all_students[:18]
        for idx, s in enumerate(present_cp2):
            a_rec = assignments_map.get(str(s.id))
            att = Attendance(
                client_uuid=uuid.uuid4(),
                trip_id=trip1.id,
                checkpoint_id=cp2.id,
                student_id=s.id,
                assignment_id=a_rec.id if a_rec else None,
                scanned_at=datetime.utcnow() - timedelta(minutes=45) + timedelta(seconds=idx * 5),
                scanned_by=teacher.id,
                scan_method="NFC",
                scan_sequence=1,
            )
            db.add(att)
        db.flush()
        print(f"[OK] {len(present_cp2)} presences scannees au checkpoint 2 (en cours)")

        # -- Voyage 2 : PLANNED (semaine prochaine) — classe B seule ----------
        next_week = date.today() + timedelta(days=7)
        trip2 = Trip(
            destination="Anvers — Musee MAS + Port",
            date=next_week,
            description="Sortie culturelle : visite du Museum aan de Stroom et du port d'Anvers.",
            status="PLANNED",
            created_by=admin.id,
        )
        db.add(trip2)
        db.flush()
        print(f"[OK] Voyage 2 : {trip2.destination} ({trip2.date}) — PLANNED")

        for s in students_b:
            db.add(TripStudent(trip_id=trip2.id, student_id=s.id))
        db.flush()

        # -- Audit logs de demo (via SQL brut, pas de modele SQLAlchemy) ------
        import json

        from sqlalchemy import text

        audit_entries = [
            (admin.id, "LOGIN", "USER", admin.id, {"method": "password"}),
            (teacher.id, "LOGIN", "USER", teacher.id, {"method": "password"}),
            (admin.id, "CREATE_TRIP", "TRIP", trip1.id, {"destination": trip1.destination}),
            (admin.id, "CREATE_TRIP", "TRIP", trip2.id, {"destination": trip2.destination}),
            (admin.id, "ASSIGN_TOKEN", "ASSIGNMENT", None, {"token_uid": "ST-001", "action": "assign"}),
            (admin.id, "IMPORT_STUDENTS", "STUDENT", None, {"count": len(all_students)}),
            (teacher.id, "CREATE_CHECKPOINT", "CHECKPOINT", cp1.id, {"name": cp1.name}),
            (teacher.id, "CREATE_CHECKPOINT", "CHECKPOINT", cp2.id, {"name": cp2.name}),
            (teacher.id, "SCAN_ATTENDANCE", "ATTENDANCE", None, {"checkpoint": cp1.name, "count": len(present_cp1)}),
        ]
        for uid, action, res_type, res_id, details in audit_entries:
            db.execute(
                text(
                    "INSERT INTO audit_logs (user_id, action, resource_type, resource_id, details) "
                    "VALUES (:uid, :action, :rtype, :rid, :details)"
                ),
                {
                    "uid": str(uid),
                    "action": action,
                    "rtype": res_type,
                    "rid": str(res_id) if res_id else None,
                    "details": json.dumps(details),
                },
            )
        print(f"[OK] {len(audit_entries)} entrees audit log")

        # -- Commit final -----------------------------------------------------
        db.commit()
        print("\n" + "=" * 60)
        print("  SEED TERMINE — Donnees de demo pretes !")
        print("=" * 60)
        print()
        print("  Comptes disponibles :")
        print("  ┌─────────────────────────────────────────────────────┐")
        print("  │ admin@schooltrack.be    / Admin123!    (DIRECTION)  │")
        print("  │ teacher@schooltrack.be  / Teacher123!  (TEACHER)    │")
        print("  │ marie.lejeune@schooltrack.be / Teacher123! (TEACHER)│")
        print("  │ obs@schooltrack.be      / Observer123! (OBSERVER)   │")
        print("  └─────────────────────────────────────────────────────┘")
        print()
        print(f"  Voyage actif : {trip1.destination} ({trip1.date})")
        print(f"    → {len(all_students)} eleves, 3 checkpoints, {len(present_cp1)} presences CP1")
        print(f"  Voyage planifie : {trip2.destination} ({trip2.date})")
        print(f"    → {len(students_b)} eleves")
        print()

    except Exception as e:
        db.rollback()
        print(f"\n[ERREUR] {e}")
        raise
    finally:
        db.close()


if __name__ == "__main__":
    seed()
