"""
Tests d'integration API pour la gestion des utilisateurs (US 6.1).
"""

import uuid
from unittest.mock import MagicMock, patch

from app.dependencies import get_current_user
from app.main import app
from app.models.user import User
from app.services.auth_service import hash_password


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def make_user(**kwargs) -> User:
    user = User()
    user.id = kwargs.get("id", uuid.uuid4())
    user.email = kwargs.get("email", "admin@school.be")
    user.password_hash = kwargs.get("password_hash", "$2b$12$fake")
    user.first_name = kwargs.get("first_name", "Admin")
    user.last_name = kwargs.get("last_name", "Test")
    user.role = kwargs.get("role", "DIRECTION")
    user.totp_secret = None
    user.is_2fa_enabled = kwargs.get("is_2fa_enabled", False)
    user.failed_attempts = 0
    user.locked_until = None
    user.last_login = None
    return user


def override_auth(user):
    app.dependency_overrides[get_current_user] = lambda: user


def cleanup_auth():
    app.dependency_overrides.pop(get_current_user, None)


# ============================================================
# GET /api/v1/users
# ============================================================

class TestListUsers:
    def test_list_users_as_direction(self, client):
        admin = make_user(role="DIRECTION")
        teacher = make_user(email="teacher@school.be", role="TEACHER", first_name="Jean")
        override_auth(admin)

        mock_db = MagicMock()
        mock_db.query.return_value.order_by.return_value.all.return_value = [admin, teacher]
        from app.database import get_db
        app.dependency_overrides[get_db] = lambda: mock_db

        resp = client.get("/api/v1/users")
        cleanup_auth()
        assert resp.status_code == 200
        assert len(resp.json()) == 2

    def test_list_users_as_teacher_forbidden(self, client):
        teacher = make_user(role="TEACHER")
        override_auth(teacher)
        resp = client.get("/api/v1/users")
        cleanup_auth()
        assert resp.status_code == 403

    def test_list_users_no_auth(self, client):
        resp = client.get("/api/v1/users")
        assert resp.status_code == 403


# ============================================================
# POST /api/v1/users
# ============================================================

class TestCreateUser:
    def test_create_user_as_direction(self, client):
        admin = make_user(role="DIRECTION")
        override_auth(admin)

        new_user = make_user(email="new@school.be", role="TEACHER", first_name="New")
        mock_db = MagicMock()
        mock_db.query.return_value.filter.return_value.first.return_value = None
        from app.database import get_db
        app.dependency_overrides[get_db] = lambda: mock_db

        with patch("app.routers.users.register_user", return_value=new_user):
            resp = client.post("/api/v1/users", json={
                "email": "new@school.be",
                "password": "NewPass1!",
                "first_name": "New",
                "last_name": "Teacher",
                "role": "TEACHER",
            })
        cleanup_auth()
        assert resp.status_code == 201
        assert resp.json()["email"] == "new@school.be"

    def test_create_user_as_teacher_forbidden(self, client):
        teacher = make_user(role="TEACHER")
        override_auth(teacher)
        resp = client.post("/api/v1/users", json={
            "email": "new@school.be",
            "password": "NewPass1!",
            "role": "TEACHER",
        })
        cleanup_auth()
        assert resp.status_code == 403

    def test_create_user_duplicate_email(self, client):
        admin = make_user(role="DIRECTION")
        override_auth(admin)
        # mock_db retourne un user existant (MagicMock truthy)
        resp = client.post("/api/v1/users", json={
            "email": "existing@school.be",
            "password": "NewPass1!",
            "role": "TEACHER",
        })
        cleanup_auth()
        assert resp.status_code == 409

    def test_create_user_weak_password(self, client):
        admin = make_user(role="DIRECTION")
        override_auth(admin)
        resp = client.post("/api/v1/users", json={
            "email": "new@school.be",
            "password": "weak",
            "role": "TEACHER",
        })
        cleanup_auth()
        assert resp.status_code == 422


# ============================================================
# DELETE /api/v1/users/{id}
# ============================================================

class TestDeleteUser:
    def test_delete_user_as_direction(self, client):
        admin = make_user(role="DIRECTION")
        target_id = uuid.uuid4()
        target = make_user(id=target_id, email="target@school.be", role="TEACHER")
        override_auth(admin)

        mock_db = MagicMock()
        mock_db.query.return_value.filter.return_value.first.return_value = target
        from app.database import get_db
        app.dependency_overrides[get_db] = lambda: mock_db

        resp = client.delete(f"/api/v1/users/{target_id}")
        cleanup_auth()
        assert resp.status_code == 204

    def test_delete_self_forbidden(self, client):
        admin = make_user(role="DIRECTION")
        override_auth(admin)
        resp = client.delete(f"/api/v1/users/{admin.id}")
        cleanup_auth()
        assert resp.status_code == 400

    def test_delete_user_as_teacher_forbidden(self, client):
        teacher = make_user(role="TEACHER")
        override_auth(teacher)
        resp = client.delete(f"/api/v1/users/{uuid.uuid4()}")
        cleanup_auth()
        assert resp.status_code == 403

    def test_delete_user_not_found(self, client):
        admin = make_user(role="DIRECTION")
        override_auth(admin)

        mock_db = MagicMock()
        mock_db.query.return_value.filter.return_value.first.return_value = None
        from app.database import get_db
        app.dependency_overrides[get_db] = lambda: mock_db

        resp = client.delete(f"/api/v1/users/{uuid.uuid4()}")
        cleanup_auth()
        assert resp.status_code == 404
