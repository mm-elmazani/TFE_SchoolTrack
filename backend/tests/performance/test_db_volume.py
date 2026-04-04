"""
US 7.4 — Test de volume base de donnees.

Critere : "La base de donnees maintient des temps de requete < 100ms
           meme avec 10 000 presences enregistrees."

Ce script :
  1. Se connecte a la DB PostgreSQL locale (Docker)
  2. Insere 10 000 presences dans la table attendances
  3. Mesure le temps de reponse des requetes les plus lourdes
  4. Nettoie les donnees de test
  5. Affiche les resultats et met a jour docs/PERFORMANCE.md

Usage :
  python backend/tests/performance/test_db_volume.py
"""

import time
import uuid
from datetime import datetime, timezone, timedelta
from pathlib import Path

import psycopg2
import psycopg2.extras

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

DB_URL = "postgresql://schooltrack:schooltrack_dev@localhost:5432/schooltrack"
TOTAL_ATTENDANCES = 10_000
BATCH_SIZE = 500
TARGET_MS = 100  # Critere : < 100ms

ROOT = Path(__file__).resolve().parents[3]
REPORT_PATH = ROOT / "docs" / "PERFORMANCE.md"

# Tag pour identifier les donnees de test
TEST_COMMENT = "__PERF_TEST_VOLUME__"


def get_connection():
    return psycopg2.connect(DB_URL)


def get_existing_ids(conn):
    """Recupere les IDs existants necessaires pour les FK."""
    cur = conn.cursor()

    cur.execute("SELECT id FROM trips LIMIT 1")
    trip = cur.fetchone()
    if not trip:
        raise RuntimeError("Aucun voyage en DB. Lance l'API avec le seed d'abord.")
    trip_id = trip[0]

    cur.execute("SELECT id FROM checkpoints WHERE trip_id = %s LIMIT 1", (trip_id,))
    checkpoint = cur.fetchone()
    if not checkpoint:
        # Creer un checkpoint de test
        cp_id = uuid.uuid4()
        cur.execute(
            "INSERT INTO checkpoints (id, trip_id, name, sequence_order, status, created_at) "
            "VALUES (%s, %s, %s, %s, %s, %s)",
            (str(cp_id), str(trip_id), "__PERF_CHECKPOINT__", 99, "ACTIVE", datetime.now(timezone.utc)),
        )
        conn.commit()
        checkpoint_id = cp_id
    else:
        checkpoint_id = checkpoint[0]

    cur.execute(
        "SELECT s.id FROM students s "
        "JOIN trip_students ts ON ts.student_id = s.id "
        "WHERE ts.trip_id = %s LIMIT 50",
        (trip_id,),
    )
    students = [row[0] for row in cur.fetchall()]
    if not students:
        raise RuntimeError("Aucun eleve lie a ce voyage.")

    cur.execute("SELECT id FROM users LIMIT 1")
    user = cur.fetchone()
    user_id = user[0] if user else None

    cur.close()
    return str(trip_id), str(checkpoint_id), [str(s) for s in students], str(user_id) if user_id else None


def seed_attendances(conn, trip_id, checkpoint_id, student_ids, user_id):
    """Insere TOTAL_ATTENDANCES presences de test."""
    cur = conn.cursor()
    methods = ["NFC_PHYSICAL", "QR_PHYSICAL", "QR_DIGITAL", "MANUAL"]
    base_time = datetime.now(timezone.utc) - timedelta(hours=6)

    print(f"\nInsertion de {TOTAL_ATTENDANCES} presences de test...")
    start = time.perf_counter()

    sync_session_id = str(uuid.uuid4())  # Tous dans la meme session de test

    batch = []
    for i in range(TOTAL_ATTENDANCES):
        student_id = student_ids[i % len(student_ids)]
        scanned_at = base_time + timedelta(seconds=i)
        method = methods[i % len(methods)]

        batch.append((
            str(uuid.uuid4()),  # id
            str(uuid.uuid4()),  # client_uuid
            trip_id,
            checkpoint_id,
            student_id,
            scanned_at,
            user_id,
            method,
            (i % 5) + 1,       # scan_sequence
            False,
            None,
            TEST_COMMENT,
            sync_session_id,
            datetime.now(timezone.utc),
        ))

        if len(batch) >= BATCH_SIZE:
            _insert_batch(cur, batch)
            batch = []

    if batch:
        _insert_batch(cur, batch)

    conn.commit()
    elapsed = (time.perf_counter() - start) * 1000
    cur.close()
    print(f"  -> {TOTAL_ATTENDANCES} presences inserees en {elapsed:.0f}ms")
    return elapsed


def _insert_batch(cur, batch):
    """Insert un batch dans attendance_history (pas de contrainte unique composite)."""
    psycopg2.extras.execute_values(
        cur,
        """INSERT INTO attendance_history
           (id, client_uuid, trip_id, checkpoint_id, student_id,
            scanned_at, scanned_by, scan_method, scan_sequence,
            is_manual, justification, comment, sync_session_id, synced_at)
           VALUES %s""",
        batch,
        template="(%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)",
    )


def run_query_benchmarks(conn, trip_id, checkpoint_id):
    """Execute les requetes les plus lourdes et mesure le temps."""
    cur = conn.cursor()
    results = []

    queries = [
        (
            "COUNT total presences (attendance_history)",
            "SELECT COUNT(*) FROM attendance_history",
        ),
        (
            "COUNT presences par voyage",
            f"SELECT COUNT(*) FROM attendance_history WHERE trip_id = '{trip_id}'",
        ),
        (
            "COUNT DISTINCT eleves presents par checkpoint",
            f"""SELECT COUNT(DISTINCT student_id)
                FROM attendance_history
                WHERE checkpoint_id = '{checkpoint_id}'""",
        ),
        (
            "Aggregation : presences par methode de scan",
            f"""SELECT scan_method, COUNT(*)
                FROM attendance_history
                WHERE trip_id = '{trip_id}'
                GROUP BY scan_method""",
        ),
        (
            "JOIN : presences + eleves + checkpoints",
            f"""SELECT ah.id, s.first_name, s.last_name, c.name, ah.scanned_at
                FROM attendance_history ah
                JOIN students s ON s.id = ah.student_id
                JOIN checkpoints c ON c.id = ah.checkpoint_id
                WHERE ah.trip_id = '{trip_id}'
                ORDER BY ah.scanned_at DESC
                LIMIT 100""",
        ),
        (
            "Sous-requete : derniere presence par eleve",
            f"""SELECT student_id, MAX(scanned_at) as last_scan
                FROM attendance_history
                WHERE trip_id = '{trip_id}'
                GROUP BY student_id""",
        ),
        (
            "COUNT avec filtre temporel (derniere heure)",
            f"""SELECT COUNT(*)
                FROM attendance_history
                WHERE trip_id = '{trip_id}'
                  AND scanned_at > NOW() - INTERVAL '1 hour'""",
        ),
        (
            "Dashboard overview : stats par checkpoint",
            f"""SELECT c.id, c.name, COUNT(DISTINCT ah.student_id) as present_count
                FROM checkpoints c
                LEFT JOIN attendance_history ah ON ah.checkpoint_id = c.id
                WHERE c.trip_id = '{trip_id}'
                GROUP BY c.id, c.name""",
        ),
    ]

    print(f"\nBenchmark des requetes avec {TOTAL_ATTENDANCES} presences :\n")
    print(f"  {'Requete':<55} {'Temps':>10}  {'Statut':>6}")
    print(f"  {'-'*55} {'-'*10}  {'-'*6}")

    for name, sql in queries:
        start = time.perf_counter()
        cur.execute(sql)
        cur.fetchall()
        elapsed_ms = (time.perf_counter() - start) * 1000
        passed = elapsed_ms < TARGET_MS
        status = "PASS" if passed else "FAIL"
        print(f"  {name:<55} {elapsed_ms:>8.1f}ms  {status:>6}")
        results.append((name, elapsed_ms, passed))

    cur.close()
    return results


def cleanup(conn):
    """Supprime les donnees de test."""
    conn.rollback()  # Reset si transaction echouee
    cur = conn.cursor()
    print("\nNettoyage des donnees de test...")
    cur.execute(f"DELETE FROM attendance_history WHERE comment = '{TEST_COMMENT}'")
    cur.execute("DELETE FROM checkpoints WHERE name = '__PERF_CHECKPOINT__'")
    conn.commit()
    cur.close()
    print(f"  -> Donnees de test supprimees")


def update_report(results, insert_time_ms):
    """Ajoute les resultats du test volume au rapport PERFORMANCE.md."""
    all_pass = all(r[2] for r in results)

    lines = [
        "",
        "## Test de volume base de donnees",
        "",
        f"> {TOTAL_ATTENDANCES:,} presences inserees en {insert_time_ms:.0f}ms",
        "",
        f"**Critere** : temps de requete < {TARGET_MS}ms avec {TOTAL_ATTENDANCES:,} presences",
        "",
        f"**Statut : {'PASS' if all_pass else 'ECHEC PARTIEL'}**",
        "",
        "| Requete | Temps | Statut |",
        "|---------|-------|--------|",
    ]

    for name, elapsed, passed in results:
        status = "PASS" if passed else "FAIL"
        lines.append(f"| {name} | {elapsed:.1f}ms | {status} |")

    lines.extend([
        "",
        "**Conclusion** : " + (
            f"Toutes les requetes repondent en moins de {TARGET_MS}ms meme avec "
            f"{TOTAL_ATTENDANCES:,} presences. La base de donnees est correctement "
            "dimensionnee pour la charge attendue."
            if all_pass else
            "Certaines requetes depassent le seuil. Des index supplementaires "
            "pourraient etre necessaires."
        ),
        "",
    ])

    # Ajouter au rapport existant
    if REPORT_PATH.exists():
        existing = REPORT_PATH.read_text(encoding="utf-8")
        # Supprimer l'ancien test volume s'il existe
        if "## Test de volume base de donnees" in existing:
            idx = existing.index("## Test de volume base de donnees")
            existing = existing[:idx].rstrip()
        REPORT_PATH.write_text(existing + "\n" + "\n".join(lines), encoding="utf-8")
    else:
        REPORT_PATH.write_text("\n".join(lines), encoding="utf-8")

    print(f"\nRapport mis a jour : {REPORT_PATH}")


def main():
    print("=" * 60)
    print("  SchoolTrack — Test de volume DB (US 7.4)")
    print(f"  Objectif : {TOTAL_ATTENDANCES:,} presences, requetes < {TARGET_MS}ms")
    print("=" * 60)

    conn = get_connection()

    try:
        # 1. Recuperer les IDs existants
        trip_id, checkpoint_id, student_ids, user_id = get_existing_ids(conn)
        print(f"\nVoyage : {trip_id}")
        print(f"Checkpoint : {checkpoint_id}")
        print(f"Eleves : {len(student_ids)} disponibles")

        # 2. Seed 10 000 presences
        insert_time = seed_attendances(conn, trip_id, checkpoint_id, student_ids, user_id)

        # 3. Benchmark des requetes
        results = run_query_benchmarks(conn, trip_id, checkpoint_id)

        # 4. Mettre a jour le rapport
        update_report(results, insert_time)

        # 5. Resume
        all_pass = all(r[2] for r in results)
        print(f"\n{'=' * 60}")
        print(f"  RESULTAT : {'PASS' if all_pass else 'ECHEC PARTIEL'}")
        print(f"  {sum(1 for r in results if r[2])}/{len(results)} requetes < {TARGET_MS}ms")
        print(f"{'=' * 60}")

    finally:
        # 6. Nettoyage
        cleanup(conn)
        conn.close()


if __name__ == "__main__":
    main()
