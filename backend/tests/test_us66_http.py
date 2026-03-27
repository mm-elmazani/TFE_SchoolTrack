"""
Tests HTTP exhaustifs - US 6.6 Multi-tenancy par école.
Crée une école CEPES, seed des données, et vérifie l'isolation complète.
Exécuter : python tests/test_us66_http.py
"""

import sys
import subprocess
import tempfile
import os
import requests

BASE = "http://localhost:8000"
PASS = 0
FAIL = 0


def ok(label):
    global PASS
    PASS += 1
    print(f"  [OK] {label}")


def ko(label, detail=""):
    global FAIL
    FAIL += 1
    print(f"  [FAIL] {label} -- {detail}")


def check(label, condition, detail=""):
    if condition:
        ok(label)
    else:
        ko(label, detail)


def login(email, password="Admin123!"):
    r = requests.post(f"{BASE}/api/v1/auth/login", json={"email": email, "password": password})
    assert r.status_code == 200, f"Login failed for {email}: {r.text}"
    data = r.json()
    token = data["access_token"]
    # Récupérer les infos utilisateur via /me
    me = requests.get(f"{BASE}/api/v1/auth/me", headers={"Authorization": f"Bearer {token}"})
    assert me.status_code == 200, f"/me failed for {email}: {me.text}"
    return token, me.json()


def auth(token):
    return {"Authorization": f"Bearer {token}"}


# ============================================================================
print("\n" + "=" * 70)
print("TEST US 6.6 - Multi-tenancy par école")
print("=" * 70)

# --------------------------------------------------------------------------
# 0. Login admin DEV
# --------------------------------------------------------------------------
print("\n--- 0. Login admin école DEV ---")
token_dev, user_dev = login("admin@schooltrack.be")
ok("Login admin DEV OK")
check("school_id dans /me", "school_id" in user_dev,
      f"user keys: {list(user_dev.keys())}")
dev_school_id = user_dev.get("school_id")

# --------------------------------------------------------------------------
# 0b. Cleanup CEPES data from previous runs
# --------------------------------------------------------------------------
print("\n--- 0b. Nettoyage donnees CEPES ---")
cleanup_sql = """
DO $$
DECLARE cepes_sid UUID;
BEGIN
    SELECT id INTO cepes_sid FROM schools WHERE slug = 'cepes';
    IF cepes_sid IS NOT NULL THEN
        DELETE FROM audit_logs WHERE user_id IN (SELECT id FROM users WHERE school_id = cepes_sid);
        DELETE FROM attendances WHERE trip_id IN (SELECT id FROM trips WHERE school_id = cepes_sid);
        DELETE FROM checkpoint_participants WHERE checkpoint_id IN (
            SELECT id FROM checkpoints WHERE trip_id IN (SELECT id FROM trips WHERE school_id = cepes_sid));
        DELETE FROM checkpoints WHERE trip_id IN (SELECT id FROM trips WHERE school_id = cepes_sid);
        DELETE FROM assignments WHERE student_id IN (SELECT id FROM students WHERE school_id = cepes_sid);
        DELETE FROM trip_students WHERE trip_id IN (SELECT id FROM trips WHERE school_id = cepes_sid);
        DELETE FROM trip_classes WHERE trip_id IN (SELECT id FROM trips WHERE school_id = cepes_sid);
        DELETE FROM trips WHERE school_id = cepes_sid;
        DELETE FROM class_students WHERE class_id IN (SELECT id FROM classes WHERE school_id = cepes_sid);
        DELETE FROM class_teachers WHERE class_id IN (SELECT id FROM classes WHERE school_id = cepes_sid);
        DELETE FROM classes WHERE school_id = cepes_sid;
        DELETE FROM students WHERE school_id = cepes_sid;
        DELETE FROM users WHERE school_id = cepes_sid;
        DELETE FROM schools WHERE slug = 'cepes';
    END IF;
END $$;
"""
with tempfile.NamedTemporaryFile(mode="w", suffix=".sql", delete=False, encoding="utf-8") as f:
    f.write(cleanup_sql)
    cleanup_path = f.name
subprocess.run(["docker", "cp", cleanup_path, "schooltrack_db:/tmp/cleanup_cepes.sql"], capture_output=True)
subprocess.run(["docker", "exec", "schooltrack_db", "psql", "-U", "schooltrack", "-d", "schooltrack",
                 "-f", "/tmp/cleanup_cepes.sql"], capture_output=True)
os.unlink(cleanup_path)
ok("Donnees CEPES nettoyees")

# --------------------------------------------------------------------------
# 1. Creer ecole CEPES via API
# --------------------------------------------------------------------------
print("\n--- 1. Creer ecole CEPES ---")
r = requests.post(f"{BASE}/api/v1/schools", json={"name": "CEPES Jodoigne", "slug": "cepes"},
                   headers=auth(token_dev))
# Seul ADMIN_TECH peut creer -> on s'attend a 403 pour DIRECTION
if r.status_code == 403:
    ok("DIRECTION ne peut pas creer d'ecole (403) - attendu")
    # Creer via SQL
    sql = "INSERT INTO schools (name, slug) VALUES ('CEPES Jodoigne', 'cepes') ON CONFLICT (slug) DO NOTHING;"
    subprocess.run(["docker", "exec", "-i", "schooltrack_db", "psql", "-U", "schooltrack", "-d", "schooltrack", "-c", sql],
                   capture_output=True)
    ok("Ecole CEPES creee via SQL")
elif r.status_code == 201:
    ok("Ecole CEPES creee via API")
elif r.status_code == 409:
    ok("Ecole CEPES existait deja (409)")
else:
    ko(f"Creation ecole CEPES inattendu: {r.status_code}", r.text)

# Récupérer les schools
r = requests.get(f"{BASE}/api/v1/schools", headers=auth(token_dev))
schools = r.json()
check("GET /schools retourne 3 écoles", len(schools) >= 3, f"got {len(schools)}")
cepes = [s for s in schools if s["slug"] == "cepes"]
check("École CEPES trouvée dans la liste", len(cepes) == 1)
cepes_id = cepes[0]["id"] if cepes else None

# --------------------------------------------------------------------------
# 2. Créer admin CEPES via SQL (bcrypt hash)
# --------------------------------------------------------------------------
print("\n--- 2. Créer admin CEPES ---")
sql_file_content = f"""
DELETE FROM users WHERE email = 'admin@cepes.be';
INSERT INTO users (email, password_hash, first_name, last_name, role, is_2fa_enabled, school_id)
VALUES (
    'admin@cepes.be',
    '$2b$12$RTrEQOYqzbhNFvIQgssaf.a7VnKy4.Hzv8AGmjd.XHxnMuRUG/fY2',
    'Directeur', 'CEPES', 'DIRECTION', FALSE,
    (SELECT id FROM schools WHERE slug = 'cepes')
);
"""
with tempfile.NamedTemporaryFile(mode="w", suffix=".sql", delete=False, encoding="utf-8") as f:
    f.write(sql_file_content)
    tmp_sql = f.name
subprocess.run(["docker", "cp", tmp_sql, "schooltrack_db:/tmp/cepes_seed.sql"], capture_output=True)
subprocess.run(["docker", "exec", "schooltrack_db", "psql", "-U", "schooltrack", "-d", "schooltrack", "-f", "/tmp/cepes_seed.sql"],
               capture_output=True)
os.unlink(tmp_sql)

token_cepes, user_cepes = login("admin@cepes.be")
ok("Login admin CEPES OK")
cepes_school_id = user_cepes["school_id"]
check("school_id CEPES = école CEPES", cepes_school_id == cepes_id,
      f"user school_id={cepes_school_id}, expected={cepes_id}")

# --------------------------------------------------------------------------
# 3. CEPES voit 0 données au départ
# --------------------------------------------------------------------------
print("\n--- 3. CEPES - données initiales vides ---")
h_cepes = auth(token_cepes)

r = requests.get(f"{BASE}/api/v1/trips", headers=h_cepes)
check("CEPES trips = 0", len(r.json()) == 0, f"got {len(r.json())}")

r = requests.get(f"{BASE}/api/v1/classes", headers=h_cepes)
check("CEPES classes = 0", len(r.json()) == 0, f"got {len(r.json())}")

r = requests.get(f"{BASE}/api/v1/students", headers=h_cepes)
check("CEPES students = 0", len(r.json()) == 0, f"got {len(r.json())}")

r = requests.get(f"{BASE}/api/v1/users", headers=h_cepes)
check("CEPES users = 1 (soi-même)", len(r.json()) == 1, f"got {len(r.json())}")

r = requests.get(f"{BASE}/api/v1/dashboard/overview", headers=h_cepes)
d = r.json()
check("CEPES dashboard trips=0, students=0",
      d["total_trips"] == 0 and d["total_students"] == 0,
      f"trips={d['total_trips']}, students={d['total_students']}")

# --------------------------------------------------------------------------
# 4. Créer des données dans CEPES
# --------------------------------------------------------------------------
print("\n--- 4. Créer données CEPES ---")

# 4a. Créer un enseignant
r = requests.post(f"{BASE}/api/v1/users", headers=h_cepes, json={
    "email": "prof@cepes.be", "password": "Prof123!Prof",
    "first_name": "Marie", "last_name": "Laurent", "role": "TEACHER"
})
check("Créer enseignant CEPES", r.status_code == 201, f"status={r.status_code}")
if r.status_code == 201:
    teacher_cepes = r.json()
    check("Enseignant school_id = CEPES", teacher_cepes["school_id"] == cepes_id)

# 4b. Créer des classes
r = requests.post(f"{BASE}/api/v1/classes", headers=h_cepes, json={"name": "3A", "year": "2025-2026"})
check("Créer classe 3A CEPES", r.status_code == 201, f"status={r.status_code}")
if r.status_code == 201:
    class_3a = r.json()
    check("Classe 3A school_id = CEPES", class_3a["school_id"] == cepes_id)
    class_3a_id = class_3a["id"]
else:
    class_3a_id = None

r = requests.post(f"{BASE}/api/v1/classes", headers=h_cepes, json={"name": "4B", "year": "2025-2026"})
check("Créer classe 4B CEPES", r.status_code == 201, f"status={r.status_code}")

# 4c. Créer des élèves
students_cepes = []
for i, (fn, ln) in enumerate([("Emma", "Dubois"), ("Lucas", "Martin"), ("Léa", "Bernard"),
                                ("Hugo", "Petit"), ("Chloé", "Leroy")]):
    r = requests.post(f"{BASE}/api/v1/students", headers=h_cepes, json={
        "first_name": fn, "last_name": ln, "email": f"{fn.lower()}@cepes.be"
    })
    check(f"Créer élève {fn} {ln}", r.status_code == 201, f"status={r.status_code}")
    if r.status_code == 201:
        s = r.json()
        check(f"Élève {fn} school_id = CEPES", s["school_id"] == cepes_id)
        students_cepes.append(s)

# 4d. Assigner élèves à la classe 3A
if class_3a_id and len(students_cepes) >= 3:
    sids = [s["id"] for s in students_cepes[:3]]
    r = requests.post(f"{BASE}/api/v1/classes/{class_3a_id}/students", headers=h_cepes,
                      json={"student_ids": sids})
    check("Assigner 3 élèves à 3A", r.status_code == 200, f"status={r.status_code}")

# 4e. Créer un voyage
if class_3a_id:
    r = requests.post(f"{BASE}/api/v1/trips", headers=h_cepes, json={
        "destination": "Bruxelles - Parlement européen",
        "date": "2026-05-15",
        "description": "Visite du Parlement",
        "class_ids": [class_3a_id]
    })
    check("Créer voyage CEPES", r.status_code == 201, f"status={r.status_code}")
    if r.status_code == 201:
        trip_cepes = r.json()
        check("Voyage school_id = CEPES", trip_cepes["school_id"] == cepes_id)
        check("Voyage a 3 élèves", trip_cepes["total_students"] == 3,
              f"got {trip_cepes['total_students']}")

# --------------------------------------------------------------------------
# 5. Vérifier isolation - DEV ne voit PAS les données CEPES
# --------------------------------------------------------------------------
print("\n--- 5. Isolation : DEV ne voit pas CEPES ---")
h_dev = auth(token_dev)

r = requests.get(f"{BASE}/api/v1/classes", headers=h_dev)
dev_classes = r.json()
cepes_class_names = [c["name"] for c in dev_classes if c.get("school_id") == cepes_id]
check("DEV ne voit pas les classes CEPES", len(cepes_class_names) == 0,
      f"classes CEPES visibles: {cepes_class_names}")

r = requests.get(f"{BASE}/api/v1/students", headers=h_dev)
dev_students = r.json()
cepes_student_names = [s["first_name"] for s in dev_students if s.get("school_id") == cepes_id]
check("DEV ne voit pas les élèves CEPES", len(cepes_student_names) == 0,
      f"élèves CEPES visibles: {cepes_student_names}")

r = requests.get(f"{BASE}/api/v1/trips", headers=h_dev)
dev_trips = r.json()
cepes_trips = [t["destination"] for t in dev_trips if t.get("school_id") == cepes_id]
check("DEV ne voit pas les voyages CEPES", len(cepes_trips) == 0,
      f"voyages CEPES visibles: {cepes_trips}")

r = requests.get(f"{BASE}/api/v1/users", headers=h_dev)
dev_users = r.json()
cepes_users = [u["email"] for u in dev_users if u.get("school_id") == cepes_id]
check("DEV ne voit pas les users CEPES", len(cepes_users) == 0,
      f"users CEPES visibles: {cepes_users}")

# --------------------------------------------------------------------------
# 6. Vérifier isolation - CEPES ne voit PAS les données DEV
# --------------------------------------------------------------------------
print("\n--- 6. Isolation : CEPES ne voit pas DEV ---")

r = requests.get(f"{BASE}/api/v1/classes", headers=h_cepes)
cepes_classes = r.json()
dev_in_cepes_classes = [c for c in cepes_classes if c.get("school_id") != cepes_id]
check("CEPES ne voit pas les classes DEV", len(dev_in_cepes_classes) == 0)
check("CEPES voit exactement 2 classes", len(cepes_classes) == 2, f"got {len(cepes_classes)}")

r = requests.get(f"{BASE}/api/v1/students", headers=h_cepes)
cepes_stu = r.json()
dev_in_cepes_stu = [s for s in cepes_stu if s.get("school_id") != cepes_id]
check("CEPES ne voit pas les élèves DEV", len(dev_in_cepes_stu) == 0)
check("CEPES voit exactement 5 élèves", len(cepes_stu) == 5, f"got {len(cepes_stu)}")

r = requests.get(f"{BASE}/api/v1/trips", headers=h_cepes)
cepes_t = r.json()
dev_in_cepes_t = [t for t in cepes_t if t.get("school_id") != cepes_id]
check("CEPES ne voit pas les voyages DEV", len(dev_in_cepes_t) == 0)
check("CEPES voit exactement 1 voyage", len(cepes_t) == 1, f"got {len(cepes_t)}")

r = requests.get(f"{BASE}/api/v1/users", headers=h_cepes)
cepes_u = r.json()
dev_in_cepes_u = [u for u in cepes_u if u.get("school_id") != cepes_id]
check("CEPES ne voit pas les users DEV", len(dev_in_cepes_u) == 0)
check("CEPES voit exactement 2 users", len(cepes_u) == 2, f"got {len(cepes_u)}")

# --------------------------------------------------------------------------
# 7. school_id présent dans TOUTES les réponses
# --------------------------------------------------------------------------
print("\n--- 7. school_id dans chaque réponse ---")

r = requests.get(f"{BASE}/api/v1/trips", headers=h_cepes)
for t in r.json():
    check(f"Trip '{t['destination']}' a school_id", "school_id" in t and t["school_id"] == cepes_id)

r = requests.get(f"{BASE}/api/v1/classes", headers=h_cepes)
for c in r.json():
    check(f"Class '{c['name']}' a school_id", "school_id" in c and c["school_id"] == cepes_id)

r = requests.get(f"{BASE}/api/v1/students", headers=h_cepes)
for s in r.json():
    check(f"Student '{s['first_name']}' a school_id", "school_id" in s and s["school_id"] == cepes_id)

r = requests.get(f"{BASE}/api/v1/users", headers=h_cepes)
for u in r.json():
    check(f"User '{u['email']}' a school_id", "school_id" in u and u["school_id"] == cepes_id)

# --------------------------------------------------------------------------
# 8. Nom de classe dupliqué entre écoles (doit fonctionner)
# --------------------------------------------------------------------------
print("\n--- 8. Classe dupliquee inter-ecole ---")
# Creer une classe avec le meme nom dans DEV et CEPES (doit fonctionner car ecoles differentes)
import random, string
dup_name = f"TestDup-{''.join(random.choices(string.ascii_uppercase, k=4))}"
r1 = requests.post(f"{BASE}/api/v1/classes", headers=h_dev, json={"name": dup_name, "year": "2025-2026"})
check(f"Classe '{dup_name}' creee dans DEV", r1.status_code == 201,
      f"status={r1.status_code}, body={r1.text[:100]}")
r2 = requests.post(f"{BASE}/api/v1/classes", headers=h_cepes, json={"name": dup_name, "year": "2025-2026"})
check(f"Classe '{dup_name}' creee dans CEPES (pas de conflit)", r2.status_code == 201,
      f"status={r2.status_code}, body={r2.text[:100]}")

# Verifier que les deux existent dans leurs ecoles respectives
r_dev = requests.get(f"{BASE}/api/v1/classes", headers=h_dev)
r_cepes = requests.get(f"{BASE}/api/v1/classes", headers=h_cepes)
dev_dup = [c for c in r_dev.json() if c["name"] == dup_name]
cepes_dup = [c for c in r_cepes.json() if c["name"] == dup_name]
check(f"DEV a sa propre classe '{dup_name}'", len(dev_dup) == 1)
check(f"CEPES a sa propre classe '{dup_name}'", len(cepes_dup) == 1)
if dev_dup and cepes_dup:
    check("Les deux classes ont des school_id differents", dev_dup[0]["school_id"] != cepes_dup[0]["school_id"])

# --------------------------------------------------------------------------
# 9. Dashboard scopé
# --------------------------------------------------------------------------
print("\n--- 9. Dashboard scopé ---")
r = requests.get(f"{BASE}/api/v1/dashboard/overview", headers=h_cepes)
d = r.json()
check("Dashboard CEPES : 1 trip", d["total_trips"] == 1, f"got {d['total_trips']}")
check("Dashboard CEPES : 3 students", d["total_students"] == 3, f"got {d['total_students']}")

r = requests.get(f"{BASE}/api/v1/dashboard/overview", headers=h_dev)
d = r.json()
check("Dashboard DEV : trips > 0", d["total_trips"] >= 1, f"got {d['total_trips']}")

# --------------------------------------------------------------------------
# 10. Sync logs scopés
# --------------------------------------------------------------------------
print("\n--- 10. Sync logs scopés ---")
r = requests.get(f"{BASE}/api/sync/stats", headers=h_cepes)
check("Sync stats CEPES = 0", r.json()["total_syncs"] == 0, f"got {r.json()['total_syncs']}")

r = requests.get(f"{BASE}/api/sync/stats", headers=h_dev)
check("Sync stats DEV >= 0", r.json()["total_syncs"] >= 0)

# --------------------------------------------------------------------------
# 11. GET /api/v1/schools
# --------------------------------------------------------------------------
print("\n--- 11. API Schools ---")
r = requests.get(f"{BASE}/api/v1/schools", headers=h_cepes)
check("CEPES peut lister les écoles", r.status_code == 200)
schools = r.json()
check("3 écoles actives", len(schools) >= 3, f"got {len(schools)}")
slugs = [s["slug"] for s in schools]
check("Slug 'dev' présent", "dev" in slugs)
check("Slug 'client' présent", "client" in slugs)
check("Slug 'cepes' présent", "cepes" in slugs)

for s in schools:
    check(f"School '{s['slug']}' a tous les champs",
          all(k in s for k in ["id", "name", "slug", "is_active", "created_at"]))

# ============================================================================
# RÉSUMÉ
# ============================================================================
print("\n" + "=" * 70)
total = PASS + FAIL
print(f"RÉSULTAT : {PASS}/{total} passés - {FAIL} échoués")
print("=" * 70)

if FAIL > 0:
    sys.exit(1)
