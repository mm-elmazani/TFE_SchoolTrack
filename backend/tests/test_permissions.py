"""
Tests des permissions par role (US 6.2).
Verifie que chaque endpoint respecte la matrice de permissions :
- DIRECTION / ADMIN_TECH : acces complet
- TEACHER : lecture + checkpoints + sync
- OBSERVER : lecture seule
"""

import uuid
from unittest.mock import MagicMock

from app.dependencies import get_current_user
from app.main import app
from app.models.user import User


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def make_user(role: str = "DIRECTION", **kwargs) -> User:
    user = User()
    user.id = kwargs.get("id", uuid.uuid4())
    user.email = kwargs.get("email", f"{role.lower()}@test.be")
    user.password_hash = "$2b$12$fake"
    user.first_name = kwargs.get("first_name", role.title())
    user.last_name = kwargs.get("last_name", "Test")
    user.role = role
    user.totp_secret = None
    user.is_2fa_enabled = False
    user.failed_attempts = 0
    user.locked_until = None
    user.last_login = None
    return user


def override_auth(user):
    app.dependency_overrides[get_current_user] = lambda: user


def cleanup():
    app.dependency_overrides.pop(get_current_user, None)


DIRECTION = make_user("DIRECTION")
ADMIN_TECH = make_user("ADMIN_TECH")
TEACHER = make_user("TEACHER")
OBSERVER = make_user("OBSERVER")


# ============================================================
# Students — GET (tous) / POST+PUT+DELETE (admin only)
# ============================================================

class TestStudentPermissions:
    """GET /students autorise tout le monde, POST/PUT/DELETE reserve admin."""

    def test_list_students_as_teacher(self, client):
        override_auth(TEACHER)
        resp = client.get("/api/v1/students")
        cleanup()
        # 200 = autorise (meme si mock DB retourne vide)
        assert resp.status_code == 200

    def test_list_students_as_observer(self, client):
        override_auth(OBSERVER)
        resp = client.get("/api/v1/students")
        cleanup()
        assert resp.status_code == 200

    def test_create_student_as_teacher_forbidden(self, client):
        override_auth(TEACHER)
        resp = client.post("/api/v1/students", json={
            "first_name": "A", "last_name": "B"
        })
        cleanup()
        assert resp.status_code == 403

    def test_create_student_as_observer_forbidden(self, client):
        override_auth(OBSERVER)
        resp = client.post("/api/v1/students", json={
            "first_name": "A", "last_name": "B"
        })
        cleanup()
        assert resp.status_code == 403

    def test_update_student_as_teacher_forbidden(self, client):
        override_auth(TEACHER)
        resp = client.put(f"/api/v1/students/{uuid.uuid4()}", json={
            "first_name": "X"
        })
        cleanup()
        assert resp.status_code == 403

    def test_delete_student_as_teacher_forbidden(self, client):
        override_auth(TEACHER)
        resp = client.delete(f"/api/v1/students/{uuid.uuid4()}")
        cleanup()
        assert resp.status_code == 403

    def test_upload_csv_as_observer_forbidden(self, client):
        override_auth(OBSERVER)
        resp = client.post(
            "/api/v1/students/upload",
            files={"file": ("test.csv", b"nom;prenom\nA;B", "text/csv")},
        )
        cleanup()
        assert resp.status_code == 403

    def test_create_student_as_admin_tech_ok(self, client):
        override_auth(ADMIN_TECH)
        mock_db = MagicMock()
        from app.database import get_db
        app.dependency_overrides[get_db] = lambda: mock_db

        mock_student = MagicMock()
        mock_student.id = uuid.uuid4()
        mock_student.first_name = "A"
        mock_student.last_name = "B"
        mock_student.email = None
        mock_student.photo_url = None
        mock_student.parent_consent = False
        mock_student.created_at = "2026-01-01T00:00:00"
        mock_student.updated_at = "2026-01-01T00:00:00"
        mock_db.refresh = lambda s: setattr(s, '__dict__', {**s.__dict__, **mock_student.__dict__})

        resp = client.post("/api/v1/students", json={
            "first_name": "A", "last_name": "B"
        })
        cleanup()
        # L'endpoint est accessible pour ADMIN_TECH (pas 403)
        assert resp.status_code != 403

    def test_no_auth_students(self, client):
        """Sans token, tous les endpoints students retournent 403."""
        app.dependency_overrides.pop(get_current_user, None)
        resp = client.get("/api/v1/students")
        assert resp.status_code == 403


# ============================================================
# Trips — GET (tous) / POST+PUT+DELETE (admin) / offline-data (field)
# ============================================================

class TestTripPermissions:
    def test_list_trips_as_observer(self, client):
        override_auth(OBSERVER)
        resp = client.get("/api/v1/trips")
        cleanup()
        assert resp.status_code == 200

    def test_create_trip_as_teacher_forbidden(self, client):
        override_auth(TEACHER)
        resp = client.post("/api/v1/trips", json={
            "destination": "Paris", "date": "2026-06-01", "class_ids": []
        })
        cleanup()
        assert resp.status_code == 403

    def test_create_trip_as_observer_forbidden(self, client):
        override_auth(OBSERVER)
        resp = client.post("/api/v1/trips", json={
            "destination": "Paris", "date": "2026-06-01", "class_ids": []
        })
        cleanup()
        assert resp.status_code == 403

    def test_update_trip_as_teacher_forbidden(self, client):
        override_auth(TEACHER)
        resp = client.put(f"/api/v1/trips/{uuid.uuid4()}", json={
            "destination": "Updated"
        })
        cleanup()
        assert resp.status_code == 403

    def test_archive_trip_as_observer_forbidden(self, client):
        override_auth(OBSERVER)
        resp = client.delete(f"/api/v1/trips/{uuid.uuid4()}")
        cleanup()
        assert resp.status_code == 403

    def test_offline_data_as_teacher_ok(self, client):
        override_auth(TEACHER)
        resp = client.get(f"/api/v1/trips/{uuid.uuid4()}/offline-data")
        cleanup()
        # Not 403 — teacher is allowed (might be 404/500 due to mock)
        assert resp.status_code != 403

    def test_offline_data_as_observer_forbidden(self, client):
        override_auth(OBSERVER)
        resp = client.get(f"/api/v1/trips/{uuid.uuid4()}/offline-data")
        cleanup()
        assert resp.status_code == 403

    def test_send_qr_emails_as_teacher_forbidden(self, client):
        override_auth(TEACHER)
        resp = client.post(f"/api/v1/trips/{uuid.uuid4()}/send-qr-emails")
        cleanup()
        assert resp.status_code == 403


# ============================================================
# Classes — GET (tous) / POST+PUT+DELETE+assign (admin)
# ============================================================

class TestClassPermissions:
    def test_list_classes_as_observer(self, client):
        override_auth(OBSERVER)
        resp = client.get("/api/v1/classes")
        cleanup()
        assert resp.status_code == 200

    def test_create_class_as_teacher_forbidden(self, client):
        override_auth(TEACHER)
        resp = client.post("/api/v1/classes", json={"name": "3A"})
        cleanup()
        assert resp.status_code == 403

    def test_update_class_as_observer_forbidden(self, client):
        override_auth(OBSERVER)
        resp = client.put(f"/api/v1/classes/{uuid.uuid4()}", json={"name": "3B"})
        cleanup()
        assert resp.status_code == 403

    def test_delete_class_as_teacher_forbidden(self, client):
        override_auth(TEACHER)
        resp = client.delete(f"/api/v1/classes/{uuid.uuid4()}")
        cleanup()
        assert resp.status_code == 403

    def test_assign_students_as_observer_forbidden(self, client):
        override_auth(OBSERVER)
        resp = client.post(
            f"/api/v1/classes/{uuid.uuid4()}/students",
            json={"student_ids": [str(uuid.uuid4())]},
        )
        cleanup()
        assert resp.status_code == 403

    def test_assign_teachers_as_teacher_forbidden(self, client):
        override_auth(TEACHER)
        resp = client.post(
            f"/api/v1/classes/{uuid.uuid4()}/teachers",
            json={"teacher_ids": [str(uuid.uuid4())]},
        )
        cleanup()
        assert resp.status_code == 403

    def test_remove_student_as_teacher_forbidden(self, client):
        override_auth(TEACHER)
        resp = client.delete(
            f"/api/v1/classes/{uuid.uuid4()}/students/{uuid.uuid4()}"
        )
        cleanup()
        assert resp.status_code == 403

    def test_list_class_students_as_teacher(self, client):
        override_auth(TEACHER)
        resp = client.get(f"/api/v1/classes/{uuid.uuid4()}/students")
        cleanup()
        assert resp.status_code != 403


# ============================================================
# Tokens — write (admin) / read (tous)
# ============================================================

class TestTokenPermissions:
    def test_assign_token_as_teacher_forbidden(self, client):
        override_auth(TEACHER)
        resp = client.post("/api/v1/tokens/assign", json={
            "token_uid": "ST-001",
            "student_id": str(uuid.uuid4()),
            "trip_id": str(uuid.uuid4()),
            "assignment_type": "NFC_PHYSICAL",
        })
        cleanup()
        assert resp.status_code == 403

    def test_reassign_token_as_observer_forbidden(self, client):
        override_auth(OBSERVER)
        resp = client.post("/api/v1/tokens/reassign", json={
            "token_uid": "ST-001",
            "student_id": str(uuid.uuid4()),
            "trip_id": str(uuid.uuid4()),
            "assignment_type": "NFC_PHYSICAL",
            "justification": "erreur",
        })
        cleanup()
        assert resp.status_code == 403

    def test_release_tokens_as_teacher_forbidden(self, client):
        override_auth(TEACHER)
        resp = client.post(f"/api/v1/trips/{uuid.uuid4()}/release-tokens")
        cleanup()
        assert resp.status_code == 403

    def test_get_trip_assignments_as_observer(self, client):
        override_auth(OBSERVER)
        resp = client.get(f"/api/v1/trips/{uuid.uuid4()}/assignments")
        cleanup()
        assert resp.status_code != 403

    def test_get_trip_students_as_teacher(self, client):
        override_auth(TEACHER)
        resp = client.get(f"/api/v1/trips/{uuid.uuid4()}/students")
        cleanup()
        assert resp.status_code != 403

    def test_export_assignments_as_observer(self, client):
        override_auth(OBSERVER)
        resp = client.get(f"/api/v1/trips/{uuid.uuid4()}/assignments/export")
        cleanup()
        assert resp.status_code != 403


# ============================================================
# Checkpoints — field roles (DIRECTION, ADMIN_TECH, TEACHER)
# ============================================================

class TestCheckpointPermissions:
    def test_create_checkpoint_as_teacher_ok(self, client):
        override_auth(TEACHER)
        resp = client.post(
            f"/api/v1/trips/{uuid.uuid4()}/checkpoints",
            json={"name": "Checkpoint 1"},
        )
        cleanup()
        assert resp.status_code != 403

    def test_create_checkpoint_as_observer_forbidden(self, client):
        override_auth(OBSERVER)
        resp = client.post(
            f"/api/v1/trips/{uuid.uuid4()}/checkpoints",
            json={"name": "Checkpoint 1"},
        )
        cleanup()
        assert resp.status_code == 403

    def test_close_checkpoint_as_teacher_ok(self, client):
        override_auth(TEACHER)
        resp = client.post(f"/api/v1/checkpoints/{uuid.uuid4()}/close")
        cleanup()
        assert resp.status_code != 403

    def test_close_checkpoint_as_observer_forbidden(self, client):
        override_auth(OBSERVER)
        resp = client.post(f"/api/v1/checkpoints/{uuid.uuid4()}/close")
        cleanup()
        assert resp.status_code == 403


# ============================================================
# Sync — field roles (DIRECTION, ADMIN_TECH, TEACHER)
# ============================================================

class TestSyncPermissions:
    def test_sync_as_teacher_ok(self, client):
        override_auth(TEACHER)
        resp = client.post("/api/sync/attendances", json={
            "device_id": "test-device",
            "scans": [],
        })
        cleanup()
        assert resp.status_code != 403

    def test_sync_as_observer_forbidden(self, client):
        override_auth(OBSERVER)
        resp = client.post("/api/sync/attendances", json={
            "device_id": "test-device",
            "scans": [],
        })
        cleanup()
        assert resp.status_code == 403


# ============================================================
# Auth — register restricted to admin (US 6.2)
# ============================================================

class TestRegisterPermissions:
    def test_register_as_direction_ok(self, client):
        override_auth(DIRECTION)
        mock_db = MagicMock()
        mock_db.query.return_value.filter.return_value.first.return_value = None
        from app.database import get_db
        app.dependency_overrides[get_db] = lambda: mock_db

        new_user = make_user("TEACHER", email="new@test.be")
        from unittest.mock import patch
        with patch("app.routers.auth.register_user", return_value=new_user):
            resp = client.post("/api/v1/auth/register", json={
                "email": "new@test.be",
                "password": "ValidPass1!",
                "role": "TEACHER",
            })
        cleanup()
        assert resp.status_code == 201

    def test_register_as_teacher_forbidden(self, client):
        override_auth(TEACHER)
        resp = client.post("/api/v1/auth/register", json={
            "email": "new@test.be",
            "password": "ValidPass1!",
            "role": "TEACHER",
        })
        cleanup()
        assert resp.status_code == 403

    def test_register_as_observer_forbidden(self, client):
        override_auth(OBSERVER)
        resp = client.post("/api/v1/auth/register", json={
            "email": "new@test.be",
            "password": "ValidPass1!",
            "role": "TEACHER",
        })
        cleanup()
        assert resp.status_code == 403

    def test_register_no_auth_forbidden(self, client):
        """Sans authentification, register retourne 403."""
        app.dependency_overrides.pop(get_current_user, None)
        resp = client.post("/api/v1/auth/register", json={
            "email": "new@test.be",
            "password": "ValidPass1!",
            "role": "TEACHER",
        })
        assert resp.status_code == 403


# ============================================================
# Users management — admin only (already tested in test_api_users)
# Quick sanity check for OBSERVER
# ============================================================

class TestUsersPermissions:
    def test_list_users_as_observer_forbidden(self, client):
        override_auth(OBSERVER)
        resp = client.get("/api/v1/users")
        cleanup()
        assert resp.status_code == 403

    def test_create_user_as_observer_forbidden(self, client):
        override_auth(OBSERVER)
        resp = client.post("/api/v1/users", json={
            "email": "new@test.be",
            "password": "ValidPass1!",
            "role": "TEACHER",
        })
        cleanup()
        assert resp.status_code == 403

    def test_delete_user_as_observer_forbidden(self, client):
        override_auth(OBSERVER)
        resp = client.delete(f"/api/v1/users/{uuid.uuid4()}")
        cleanup()
        assert resp.status_code == 403


# ============================================================
# require_role unit test
# ============================================================

class TestRequireRoleFactory:
    """Teste la fabrique require_role() directement."""

    def test_allowed_role_passes(self):
        from app.dependencies import require_role
        checker = require_role("DIRECTION", "TEACHER")
        user = make_user("TEACHER")
        result = checker(current_user=user)
        assert result.role == "TEACHER"

    def test_disallowed_role_raises(self):
        import pytest
        from fastapi import HTTPException
        from app.dependencies import require_role
        checker = require_role("DIRECTION")
        user = make_user("OBSERVER")
        with pytest.raises(HTTPException) as exc_info:
            checker(current_user=user)
        assert exc_info.value.status_code == 403
