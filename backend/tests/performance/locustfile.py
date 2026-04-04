"""
US 7.4 — Tests de performance et charge SchoolTrack.

Scenarios Locust :
  1. Sync massif : 5 enseignants synchronisent 200 presences chacun (1000 total)
  2. Endpoints critiques : login, liste voyages, dashboard, checkpoints
  3. Requetes concurrentes sur l'API sous charge

Criteres d'acceptation :
  - < 500ms pour 95% des requetes sous charge
  - 20 req/sec sans degradation
  - DB < 100ms avec 10 000 presences

Lancer :
  locust -f backend/tests/performance/locustfile.py --headless \
    -u 5 -r 1 --run-time 60s --host http://localhost:8000 \
    --csv results/perf
"""

import random
import uuid
from datetime import datetime, timezone

from locust import HttpUser, between, task


# ---------------------------------------------------------------------------
# Configuration — adapter selon l'environnement
# ---------------------------------------------------------------------------

TEACHER_EMAIL = "teacher@schooltrack.be"
TEACHER_PASSWORD = "Teacher123!"

ADMIN_EMAIL = "admin@schooltrack.be"
ADMIN_PASSWORD = "Admin123!"

SCAN_METHODS = ["NFC_PHYSICAL", "QR_PHYSICAL", "QR_DIGITAL", "MANUAL"]


class SchoolTrackTeacher(HttpUser):
    """
    Simule un enseignant sur le terrain :
      - Login
      - Consulte ses voyages
      - Telecharge des bundles offline
      - Synchronise des presences par batch de 200
    """

    wait_time = between(0.1, 0.5)
    weight = 4

    def on_start(self):
        """Authentification au demarrage."""
        resp = self.client.post(
            "/api/v1/auth/login",
            json={"email": TEACHER_EMAIL, "password": TEACHER_PASSWORD},
            name="POST /auth/login",
        )
        if resp.status_code == 200:
            data = resp.json()
            self.token = data.get("access_token", "")
            self.headers = {"Authorization": f"Bearer {self.token}"}
        else:
            self.token = ""
            self.headers = {}

        self.trip_ids = []
        self.checkpoint_ids = []
        self.student_ids = []
        self._load_trip_data()

    def _load_trip_data(self):
        """Charge les donnees de voyages pour les scans."""
        resp = self.client.get(
            "/api/v1/trips",
            headers=self.headers,
            name="GET /trips (setup)",
        )
        if resp.status_code != 200:
            return

        trips = resp.json()
        if not isinstance(trips, list):
            return

        for trip in trips[:3]:
            tid = trip.get("id")
            if tid:
                self.trip_ids.append(tid)

        # Recuperer les eleves et checkpoints via offline-data
        for tid in self.trip_ids:
            resp = self.client.get(
                f"/api/v1/trips/{tid}/offline-data",
                headers=self.headers,
                name="GET /trips/{{id}}/offline-data (setup)",
            )
            if resp.status_code == 200:
                bundle = resp.json()
                self.student_ids.extend(
                    s["id"] for s in bundle.get("students", [])
                )
                self.checkpoint_ids.extend(
                    c["id"] for c in bundle.get("checkpoints", [])
                )
                break  # Un seul bundle suffit

    @task(3)
    def sync_attendances_batch(self):
        """
        Synchronise un batch de 200 presences (scenario critique US 7.4).
        Si pas de donnees de voyage, genere des UUIDs synthetiques
        (le backend les rejettera proprement mais le test de charge mesure
        le temps de traitement du batch).
        """
        trip_id = random.choice(self.trip_ids) if self.trip_ids else str(uuid.uuid4())
        checkpoint_id = random.choice(self.checkpoint_ids) if self.checkpoint_ids else str(uuid.uuid4())

        scans = []
        for _ in range(200):
            student_id = random.choice(self.student_ids) if self.student_ids else str(uuid.uuid4())
            scans.append({
                "client_uuid": str(uuid.uuid4()),
                "student_id": student_id,
                "checkpoint_id": checkpoint_id,
                "trip_id": trip_id,
                "scanned_at": datetime.now(timezone.utc).isoformat(),
                "scan_method": random.choice(SCAN_METHODS),
                "scan_sequence": 1,
                "is_manual": False,
            })

        self.client.post(
            "/api/sync/attendances",
            json={"scans": scans, "device_id": f"locust-{self.greenlet.minimal_ident}"},
            headers=self.headers,
            name="POST /sync/attendances (200 scans)",
        )

    @task(2)
    def get_trips_list(self):
        """Consulte la liste des voyages."""
        self.client.get(
            "/api/v1/trips",
            headers=self.headers,
            name="GET /trips",
        )

    @task(1)
    def get_offline_data(self):
        """Telecharge le bundle offline d'un voyage."""
        if not self.trip_ids:
            return
        trip_id = random.choice(self.trip_ids)
        self.client.get(
            f"/api/v1/trips/{trip_id}/offline-data",
            headers=self.headers,
            name="GET /trips/{{id}}/offline-data",
        )

    @task(1)
    def get_trip_detail(self):
        """Consulte le detail d'un voyage."""
        if not self.trip_ids:
            return
        trip_id = random.choice(self.trip_ids)
        self.client.get(
            f"/api/v1/trips/{trip_id}",
            headers=self.headers,
            name="GET /trips/{{id}}",
        )


class SchoolTrackDirection(HttpUser):
    """
    Simule un utilisateur direction consultant le dashboard.
    Poids 1 (vs 4 pour enseignants → ratio 4:1).
    """

    weight = 1
    wait_time = between(0.2, 0.8)

    def on_start(self):
        resp = self.client.post(
            "/api/v1/auth/login",
            json={"email": ADMIN_EMAIL, "password": ADMIN_PASSWORD},
            name="POST /auth/login",
        )
        if resp.status_code == 200:
            data = resp.json()
            self.token = data.get("access_token", "")
            self.headers = {"Authorization": f"Bearer {self.token}"}
        else:
            self.token = ""
            self.headers = {}

    @task(3)
    def get_dashboard(self):
        """Consulte le tableau de bord."""
        self.client.get(
            "/api/v1/dashboard/overview",
            headers=self.headers,
            name="GET /dashboard/overview",
        )

    @task(2)
    def get_sync_logs(self):
        """Consulte les logs de synchronisation."""
        self.client.get(
            "/api/sync/logs?page=1&page_size=20",
            headers=self.headers,
            name="GET /sync/logs",
        )

    @task(1)
    def get_sync_stats(self):
        """Consulte les statistiques de synchronisation."""
        self.client.get(
            "/api/sync/stats",
            headers=self.headers,
            name="GET /sync/stats",
        )

    @task(2)
    def get_students(self):
        """Consulte la liste des eleves."""
        self.client.get(
            "/api/v1/students",
            headers=self.headers,
            name="GET /students",
        )

    @task(1)
    def get_audit_logs(self):
        """Consulte les logs d'audit."""
        self.client.get(
            "/api/v1/audit/logs?page=1&page_size=20",
            headers=self.headers,
            name="GET /audit/logs",
        )
