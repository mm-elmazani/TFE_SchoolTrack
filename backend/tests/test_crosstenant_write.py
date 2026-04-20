"""
Tests d'isolation multi-tenant (US 6.6) — endpoints PUT/DELETE.

Vérifie que chaque endpoint d'écriture par ID (students, classes, trips, users)
filtre bien par `school_id` du JWT et renvoie 404 quand la ressource
appartient à une autre école.

Stratégie : on mocke `db.execute(...).scalar_one_or_none()` pour renvoyer None
(simule "l'objet existe en DB mais pas dans l'école du user courant").
"""

import uuid
from unittest.mock import MagicMock

from app.database import get_db
from app.main import app


def _mock_db_returns_none():
    """Renvoie un mock DB où toutes les lookups scalar_one_or_none() retournent None."""
    db = MagicMock()
    db.execute.return_value.scalar_one_or_none.return_value = None
    # Pour les services qui utilisent db.get() (classes, users via query().filter().first())
    db.get.return_value = None
    db.query.return_value.filter.return_value.first.return_value = None
    return db


# ============================================================================
# Students — PUT, DELETE, photo, export GDPR
# ============================================================================

class TestStudentCrossTenant:

    def test_update_student_autre_ecole_404(self, client):
        """PUT /students/{id} renvoie 404 si l'élève est dans une autre école."""
        db = _mock_db_returns_none()
        app.dependency_overrides[get_db] = lambda: db
        other_school_student_id = str(uuid.uuid4())

        resp = client.put(
            f"/api/v1/students/{other_school_student_id}",
            json={"first_name": "Hacked"},
        )
        app.dependency_overrides.clear()

        assert resp.status_code == 404

    def test_delete_student_autre_ecole_404(self, client):
        """DELETE /students/{id} renvoie 404 si l'élève est dans une autre école."""
        db = _mock_db_returns_none()
        app.dependency_overrides[get_db] = lambda: db
        other_school_student_id = str(uuid.uuid4())

        resp = client.delete(f"/api/v1/students/{other_school_student_id}")
        app.dependency_overrides.clear()

        assert resp.status_code == 404

    def test_export_gdpr_autre_ecole_404(self, client):
        """GET /students/{id}/data-export renvoie 404 si l'élève est dans une autre école."""
        db = _mock_db_returns_none()
        app.dependency_overrides[get_db] = lambda: db
        other_school_student_id = str(uuid.uuid4())

        resp = client.get(f"/api/v1/students/{other_school_student_id}/data-export")
        app.dependency_overrides.clear()

        assert resp.status_code == 404

    def test_photo_get_autre_ecole_404(self, client):
        """GET /students/{id}/photo renvoie 404 si l'élève est dans une autre école."""
        db = _mock_db_returns_none()
        app.dependency_overrides[get_db] = lambda: db
        other_school_student_id = str(uuid.uuid4())

        resp = client.get(f"/api/v1/students/{other_school_student_id}/photo")
        app.dependency_overrides.clear()

        assert resp.status_code == 404


# ============================================================================
# Classes — PUT, DELETE, assign students/teachers
# ============================================================================

class TestClassCrossTenant:

    def test_update_class_autre_ecole_404(self, client):
        db = _mock_db_returns_none()
        app.dependency_overrides[get_db] = lambda: db
        other_class_id = str(uuid.uuid4())

        resp = client.put(
            f"/api/v1/classes/{other_class_id}",
            json={"name": "Hacked"},
        )
        app.dependency_overrides.clear()

        assert resp.status_code == 404

    def test_delete_class_autre_ecole_404(self, client):
        db = _mock_db_returns_none()
        app.dependency_overrides[get_db] = lambda: db
        other_class_id = str(uuid.uuid4())

        resp = client.delete(f"/api/v1/classes/{other_class_id}")
        app.dependency_overrides.clear()

        assert resp.status_code == 404

    def test_get_class_autre_ecole_404(self, client):
        db = _mock_db_returns_none()
        app.dependency_overrides[get_db] = lambda: db
        other_class_id = str(uuid.uuid4())

        resp = client.get(f"/api/v1/classes/{other_class_id}")
        app.dependency_overrides.clear()

        assert resp.status_code == 404

    def test_assign_students_autre_ecole_404(self, client):
        db = _mock_db_returns_none()
        app.dependency_overrides[get_db] = lambda: db
        other_class_id = str(uuid.uuid4())

        resp = client.post(
            f"/api/v1/classes/{other_class_id}/students",
            json={"student_ids": [str(uuid.uuid4())]},
        )
        app.dependency_overrides.clear()

        assert resp.status_code == 404


# ============================================================================
# Trips — PUT, DELETE, export, offline-data, send-qr-emails
# ============================================================================

class TestTripCrossTenant:

    def test_update_trip_autre_ecole_404(self, client):
        db = _mock_db_returns_none()
        app.dependency_overrides[get_db] = lambda: db
        other_trip_id = str(uuid.uuid4())

        resp = client.put(
            f"/api/v1/trips/{other_trip_id}",
            json={"destination": "Hacked"},
        )
        app.dependency_overrides.clear()

        assert resp.status_code == 404

    def test_archive_trip_autre_ecole_404(self, client):
        db = _mock_db_returns_none()
        app.dependency_overrides[get_db] = lambda: db
        other_trip_id = str(uuid.uuid4())

        resp = client.delete(f"/api/v1/trips/{other_trip_id}")
        app.dependency_overrides.clear()

        assert resp.status_code == 404

    def test_get_trip_autre_ecole_404(self, client):
        db = _mock_db_returns_none()
        app.dependency_overrides[get_db] = lambda: db
        other_trip_id = str(uuid.uuid4())

        resp = client.get(f"/api/v1/trips/{other_trip_id}")
        app.dependency_overrides.clear()

        assert resp.status_code == 404

    def test_export_csv_autre_ecole_404(self, client):
        """GET /trips/{id}/export : service lève ValueError → 404."""
        db = MagicMock()
        # scalar_one_or_none pour _get_owned_trip → None
        db.execute.return_value.scalar_one_or_none.return_value = None
        # Aussi db.get (dans le _to_response et autres) → None
        db.get.return_value = None
        app.dependency_overrides[get_db] = lambda: db
        other_trip_id = str(uuid.uuid4())

        resp = client.get(f"/api/v1/trips/{other_trip_id}/export")
        app.dependency_overrides.clear()

        assert resp.status_code == 404

    def test_offline_data_autre_ecole_404(self, client):
        """GET /trips/{id}/offline-data : service lève ValueError → 404."""
        db = MagicMock()
        db.execute.return_value.scalar.return_value = None
        db.execute.return_value.scalar_one_or_none.return_value = None
        app.dependency_overrides[get_db] = lambda: db
        other_trip_id = str(uuid.uuid4())

        resp = client.get(f"/api/v1/trips/{other_trip_id}/offline-data")
        app.dependency_overrides.clear()

        assert resp.status_code == 404


# ============================================================================
# Users — DELETE
# ============================================================================

class TestUserCrossTenant:

    def test_delete_user_autre_ecole_404(self, client):
        """DELETE /users/{id} renvoie 404 si l'utilisateur est dans une autre école."""
        db = _mock_db_returns_none()
        app.dependency_overrides[get_db] = lambda: db
        other_user_id = str(uuid.uuid4())

        resp = client.delete(f"/api/v1/users/{other_user_id}")
        app.dependency_overrides.clear()

        assert resp.status_code == 404
