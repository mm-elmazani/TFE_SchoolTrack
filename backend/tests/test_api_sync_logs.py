"""
Tests d'intégration API pour les endpoints de consultation des sync_logs.

Endpoints couverts :
- GET /api/sync/logs — liste paginée des journaux de synchronisation
- GET /api/sync/stats — statistiques globales de synchronisation
- Filtrage par statut
- Pagination
- Permissions (admin uniquement)
"""

import uuid
from datetime import datetime
from unittest.mock import MagicMock, patch

from app.models.sync_log import SyncLog
from app.models.user import User
from app.schemas.sync import SyncLogPage, SyncLogOut, SyncStats


# ----------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------

def make_sync_log(
    id=1,
    user_id=None,
    trip_id=None,
    device_id="flutter-device-01",
    records_synced=5,
    conflicts_detected=0,
    status="SUCCESS",
    synced_at=None,
):
    log = MagicMock(spec=SyncLog)
    log.id = id
    log.user_id = user_id or uuid.uuid4()
    log.trip_id = trip_id or uuid.uuid4()
    log.device_id = device_id
    log.records_synced = records_synced
    log.conflicts_detected = conflicts_detected
    log.status = status
    log.error_details = {
        "total_received": records_synced + conflicts_detected,
        "accepted": records_synced,
        "merged": 0,
        "duplicate": conflicts_detected,
        "rejected": 0,
        "anomalies": 0,
    }
    log.synced_at = synced_at or datetime(2026, 3, 23, 14, 30, 0)
    return log


# ================================================================
# GET /api/sync/logs
# ================================================================

class TestGetSyncLogs:

    def test_sync_logs_200_vide(self, client):
        """Aucun log → 200 avec items=[], total=0."""
        from app.database import get_db
        from app.main import app

        def mock_get_db():
            db = MagicMock()
            mock_count = MagicMock()
            mock_count.scalar.return_value = 0
            mock_rows = MagicMock()
            mock_rows.scalars.return_value.all.return_value = []
            db.execute.side_effect = [mock_count, mock_rows]
            return db

        app.dependency_overrides[get_db] = mock_get_db

        response = client.get("/api/sync/logs")

        assert response.status_code == 200
        data = response.json()
        assert data["items"] == []
        assert data["total"] == 0
        assert data["page"] == 1

    def test_sync_logs_200_avec_donnees(self, client):
        """Logs existants → 200 avec données paginées."""
        user_id = uuid.uuid4()
        trip_id = uuid.uuid4()
        log1 = make_sync_log(id=1, user_id=user_id, trip_id=trip_id)

        from app.database import get_db
        from app.main import app

        def mock_get_db():
            db = MagicMock()
            # count query
            count_result = MagicMock()
            count_result.scalar.return_value = 1
            # rows query
            rows_result = MagicMock()
            rows_result.scalars.return_value.all.return_value = [log1]
            # user lookup
            user_row = MagicMock()
            user_row.id = user_id
            user_row.email = "teacher@schooltrack.be"
            users_result = MagicMock()
            users_result.all.return_value = [user_row]
            # trip lookup
            trip_row = MagicMock()
            trip_row.id = trip_id
            trip_row.destination = "Paris"
            trips_result = MagicMock()
            trips_result.all.return_value = [trip_row]

            db.execute.side_effect = [count_result, rows_result, users_result, trips_result]
            return db

        app.dependency_overrides[get_db] = mock_get_db

        response = client.get("/api/sync/logs")

        assert response.status_code == 200
        data = response.json()
        assert data["total"] == 1
        assert len(data["items"]) == 1
        item = data["items"][0]
        assert item["id"] == 1
        assert item["user_email"] == "teacher@schooltrack.be"
        assert item["trip_name"] == "Paris"
        assert item["records_synced"] == 5
        assert item["status"] == "SUCCESS"

    def test_sync_logs_pagination(self, client):
        """page=2, page_size=1 → offset correctement appliqué."""
        from app.database import get_db
        from app.main import app

        def mock_get_db():
            db = MagicMock()
            count_result = MagicMock()
            count_result.scalar.return_value = 5
            rows_result = MagicMock()
            rows_result.scalars.return_value.all.return_value = [make_sync_log(id=2)]
            db.execute.side_effect = [count_result, rows_result, MagicMock(all=MagicMock(return_value=[])), MagicMock(all=MagicMock(return_value=[]))]
            return db

        app.dependency_overrides[get_db] = mock_get_db

        response = client.get("/api/sync/logs?page=2&page_size=1")

        assert response.status_code == 200
        data = response.json()
        assert data["page"] == 2
        assert data["total"] == 5
        assert data["total_pages"] == 5

    def test_sync_logs_filtre_statut(self, client):
        """Filtre par status=PARTIAL → requête filtrée."""
        from app.database import get_db
        from app.main import app

        def mock_get_db():
            db = MagicMock()
            count_result = MagicMock()
            count_result.scalar.return_value = 0
            rows_result = MagicMock()
            rows_result.scalars.return_value.all.return_value = []
            db.execute.side_effect = [count_result, rows_result]
            return db

        app.dependency_overrides[get_db] = mock_get_db

        response = client.get("/api/sync/logs?status=PARTIAL")

        assert response.status_code == 200


# ================================================================
# GET /api/sync/stats
# ================================================================

class TestGetSyncStats:

    def test_sync_stats_200(self, client):
        """Stats globales → 200 avec compteurs."""
        from app.database import get_db
        from app.main import app

        def mock_get_db():
            db = MagicMock()
            # total_syncs, total_synced, total_conflicts, success, partial, failed, last_sync
            results = [10, 150, 5, 8, 1, 1, datetime(2026, 3, 23, 15, 0, 0)]
            side_effects = []
            for v in results:
                m = MagicMock()
                m.scalar.return_value = v
                side_effects.append(m)
            db.execute.side_effect = side_effects
            return db

        app.dependency_overrides[get_db] = mock_get_db

        response = client.get("/api/sync/stats")

        assert response.status_code == 200
        data = response.json()
        assert data["total_syncs"] == 10
        assert data["total_records_synced"] == 150
        assert data["total_conflicts"] == 5
        assert data["success_count"] == 8
        assert data["partial_count"] == 1
        assert data["failed_count"] == 1
        assert data["last_sync_at"] is not None

    def test_sync_stats_vide(self, client):
        """Aucune sync → compteurs à 0, last_sync_at=None."""
        from app.database import get_db
        from app.main import app

        def mock_get_db():
            db = MagicMock()
            results = [0, 0, 0, 0, 0, 0, None]
            side_effects = []
            for v in results:
                m = MagicMock()
                m.scalar.return_value = v
                side_effects.append(m)
            db.execute.side_effect = side_effects
            return db

        app.dependency_overrides[get_db] = mock_get_db

        response = client.get("/api/sync/stats")

        assert response.status_code == 200
        data = response.json()
        assert data["total_syncs"] == 0
        assert data["last_sync_at"] is None


# ================================================================
# Permissions — seuls DIRECTION / ADMIN_TECH
# ================================================================

class TestSyncLogsPermissions:

    def test_teacher_interdit_logs(self, client):
        """Un TEACHER ne peut pas accéder aux sync_logs."""
        from app.dependencies import get_current_user
        from app.main import app

        teacher = User()
        teacher.id = uuid.uuid4()
        teacher.email = "prof@schooltrack.be"
        teacher.password_hash = "$2b$12$fake"
        teacher.first_name = "Prof"
        teacher.last_name = "Test"
        teacher.role = "TEACHER"
        teacher.totp_secret = None
        teacher.is_2fa_enabled = False
        teacher.failed_attempts = 0
        teacher.locked_until = None
        teacher.last_login = None

        app.dependency_overrides[get_current_user] = lambda: teacher

        response = client.get("/api/sync/logs")
        assert response.status_code == 403

        response = client.get("/api/sync/stats")
        assert response.status_code == 403

        # Remettre l'override par défaut (conftest le fera aussi)
        app.dependency_overrides.pop(get_current_user, None)


# ================================================================
# Validation des schémas Pydantic
# ================================================================

class TestSyncSchemas:

    def test_sync_log_out_serialization(self):
        """SyncLogOut se sérialise correctement."""
        log = SyncLogOut(
            id=1,
            user_id=str(uuid.uuid4()),
            user_email="admin@schooltrack.be",
            trip_id=str(uuid.uuid4()),
            trip_name="Paris",
            device_id="flutter-01",
            records_synced=10,
            conflicts_detected=2,
            status="SUCCESS",
            error_details={"accepted": 10, "duplicate": 2},
            synced_at=datetime(2026, 3, 23, 14, 0, 0),
        )
        data = log.model_dump()
        assert data["id"] == 1
        assert data["user_email"] == "admin@schooltrack.be"
        assert data["records_synced"] == 10

    def test_sync_stats_serialization(self):
        """SyncStats se sérialise correctement."""
        stats = SyncStats(
            total_syncs=50,
            total_records_synced=1000,
            total_conflicts=30,
            success_count=45,
            partial_count=3,
            failed_count=2,
            last_sync_at=datetime(2026, 3, 23, 15, 0, 0),
        )
        data = stats.model_dump()
        assert data["total_syncs"] == 50
        assert data["success_count"] == 45

    def test_sync_log_page_serialization(self):
        """SyncLogPage structure correcte."""
        page = SyncLogPage(
            items=[],
            total=0,
            page=1,
            page_size=20,
            total_pages=1,
        )
        data = page.model_dump()
        assert data["items"] == []
        assert data["total_pages"] == 1
