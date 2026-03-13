"""
Tests pour l'export CSV des presences (US 4.1).
Service export_attendance_csv + endpoints /export et /export-all.
"""

import io
import uuid
import zipfile
from datetime import date, datetime
from unittest.mock import MagicMock, patch, PropertyMock

import pytest


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _make_trip(trip_id=None, destination="Bruges", trip_date=None, status="ACTIVE"):
    """Cree un objet Trip mocke."""
    trip = MagicMock()
    trip.id = trip_id or uuid.uuid4()
    trip.destination = destination
    trip.date = trip_date or date(2026, 3, 15)
    trip.description = "Sortie culturelle"
    trip.status = status
    trip.created_at = datetime(2026, 3, 1, 10, 0)
    trip.updated_at = datetime(2026, 3, 1, 10, 0)
    return trip


def _make_student(student_id=None, first_name="Marie", last_name="Dupont", is_deleted=False):
    """Cree un objet Student mocke."""
    s = MagicMock()
    s.id = student_id or uuid.uuid4()
    s.first_name = first_name
    s.last_name = last_name
    s.is_deleted = is_deleted
    return s


def _make_checkpoint(cp_id=None, name="Depart gare", sequence_order=1, trip_id=None):
    """Cree un objet Checkpoint mocke."""
    cp = MagicMock()
    cp.id = cp_id or uuid.uuid4()
    cp.name = name
    cp.sequence_order = sequence_order
    cp.trip_id = trip_id
    return cp


def _make_attendance(student_id, checkpoint_id, trip_id, scan_method="NFC",
                     scanned_at=None, justification=None):
    """Cree un objet Attendance mocke."""
    att = MagicMock()
    att.id = uuid.uuid4()
    att.student_id = student_id
    att.checkpoint_id = checkpoint_id
    att.trip_id = trip_id
    att.scan_method = scan_method
    att.scanned_at = scanned_at or datetime(2026, 3, 15, 8, 15, 32)
    att.justification = justification
    return att


# ============================================================
# Tests SERVICE — export_attendance_csv
# ============================================================


class TestExportAttendanceCsv:
    """Tests unitaires pour trip_service.export_attendance_csv."""

    def test_trip_not_found(self):
        """Voyage introuvable → ValueError."""
        from app.services import trip_service

        db = MagicMock()
        db.get.return_value = None

        with pytest.raises(ValueError, match="introuvable"):
            trip_service.export_attendance_csv(db, uuid.uuid4())

    def test_csv_empty_no_attendances(self):
        """Voyage sans presences → CSV avec metadonnees et header, aucune ligne de donnees."""
        from app.services import trip_service

        trip = _make_trip()
        db = MagicMock()
        db.get.return_value = trip

        # total students = 3
        mock_scalar = MagicMock()
        mock_scalar.scalar.return_value = 3

        # Pas de class_rows, pas d'attendances, pas de checkpoints ordonnes
        mock_class = MagicMock()
        mock_class.all.return_value = []

        mock_att = MagicMock()
        mock_att.all.return_value = []

        mock_cps = MagicMock()
        mock_cps_scalars = MagicMock()
        mock_cps_scalars.all.return_value = []
        mock_cps.scalars.return_value = mock_cps_scalars

        # db.execute retourne dans l'ordre: total, class_rows, attendances, checkpoints
        db.execute.side_effect = [mock_scalar, mock_class, mock_att, mock_cps]

        csv_str, returned_trip = trip_service.export_attendance_csv(db, trip.id)

        assert returned_trip is trip
        assert "\ufeff" in csv_str  # BOM UTF-8
        assert "# Voyage : Bruges" in csv_str
        assert "# Total eleves : 3" in csv_str
        assert "Nom;Prenom;Classe;Checkpoint" in csv_str

    def test_csv_with_data(self):
        """Voyage avec presences → lignes CSV correctes."""
        from app.services import trip_service

        trip = _make_trip()
        student = _make_student(first_name="Marie", last_name="Dupont")
        cp = _make_checkpoint(name="Depart gare", sequence_order=1, trip_id=trip.id)
        att = _make_attendance(student.id, cp.id, trip.id, scan_method="NFC")

        db = MagicMock()
        db.get.return_value = trip

        # total students = 2
        mock_scalar = MagicMock()
        mock_scalar.scalar.return_value = 2

        # class_map
        mock_class = MagicMock()
        mock_class.all.return_value = [(student.id, "3TI-A")]

        # attendances
        mock_att = MagicMock()
        mock_att.all.return_value = [(att, student, cp)]

        # ordered checkpoints
        mock_cps = MagicMock()
        mock_cps_scalars = MagicMock()
        mock_cps_scalars.all.return_value = [cp]
        mock_cps.scalars.return_value = mock_cps_scalars

        db.execute.side_effect = [mock_scalar, mock_class, mock_att, mock_cps]

        csv_str, _ = trip_service.export_attendance_csv(db, trip.id)

        assert "Dupont;Marie;3TI-A;Depart gare;08:15:32;NFC;" in csv_str
        assert "# Depart gare : 50%" in csv_str  # 1/2 = 50%

    def test_csv_deleted_student(self):
        """Eleve soft-deleted → affiche [Supprime]."""
        from app.services import trip_service

        trip = _make_trip()
        student = _make_student(first_name="John", last_name="Doe", is_deleted=True)
        cp = _make_checkpoint(name="Arrivee", sequence_order=1, trip_id=trip.id)
        att = _make_attendance(student.id, cp.id, trip.id)

        db = MagicMock()
        db.get.return_value = trip

        mock_scalar = MagicMock()
        mock_scalar.scalar.return_value = 1

        mock_class = MagicMock()
        mock_class.all.return_value = []

        mock_att = MagicMock()
        mock_att.all.return_value = [(att, student, cp)]

        mock_cps = MagicMock()
        mock_cps_scalars = MagicMock()
        mock_cps_scalars.all.return_value = [cp]
        mock_cps.scalars.return_value = mock_cps_scalars

        db.execute.side_effect = [mock_scalar, mock_class, mock_att, mock_cps]

        csv_str, _ = trip_service.export_attendance_csv(db, trip.id)

        assert "[Supprime];[Supprime]" in csv_str

    def test_bom_present(self):
        """Le CSV commence par le BOM UTF-8."""
        from app.services import trip_service

        trip = _make_trip()
        db = MagicMock()
        db.get.return_value = trip

        mock_scalar = MagicMock()
        mock_scalar.scalar.return_value = 0
        mock_empty = MagicMock()
        mock_empty.all.return_value = []
        mock_cps = MagicMock()
        mock_cps_scalars = MagicMock()
        mock_cps_scalars.all.return_value = []
        mock_cps.scalars.return_value = mock_cps_scalars

        db.execute.side_effect = [mock_scalar, mock_empty, mock_empty, mock_cps]

        csv_str, _ = trip_service.export_attendance_csv(db, trip.id)
        assert csv_str.startswith("\ufeff")

    def test_csv_metadata_format(self):
        """Les metadonnees contiennent la destination et la date au bon format."""
        from app.services import trip_service

        trip = _make_trip(destination="Anvers", trip_date=date(2026, 5, 20))
        db = MagicMock()
        db.get.return_value = trip

        mock_scalar = MagicMock()
        mock_scalar.scalar.return_value = 0
        mock_empty = MagicMock()
        mock_empty.all.return_value = []
        mock_cps = MagicMock()
        mock_cps_scalars = MagicMock()
        mock_cps_scalars.all.return_value = []
        mock_cps.scalars.return_value = mock_cps_scalars

        db.execute.side_effect = [mock_scalar, mock_empty, mock_empty, mock_cps]

        csv_str, _ = trip_service.export_attendance_csv(db, trip.id)

        assert "# Voyage : Anvers" in csv_str
        assert "# Date : 20/05/2026" in csv_str

    def test_attendance_rate_calculation(self):
        """Taux de presence calcule correctement (2 eleves scannes / 4 total = 50%)."""
        from app.services import trip_service

        trip = _make_trip()
        s1 = _make_student(first_name="A", last_name="A")
        s2 = _make_student(first_name="B", last_name="B")
        cp = _make_checkpoint(name="Check1", sequence_order=1, trip_id=trip.id)
        att1 = _make_attendance(s1.id, cp.id, trip.id)
        att2 = _make_attendance(s2.id, cp.id, trip.id)

        db = MagicMock()
        db.get.return_value = trip

        mock_scalar = MagicMock()
        mock_scalar.scalar.return_value = 4  # 4 eleves inscrits

        mock_class = MagicMock()
        mock_class.all.return_value = []

        mock_att = MagicMock()
        mock_att.all.return_value = [(att1, s1, cp), (att2, s2, cp)]

        mock_cps = MagicMock()
        mock_cps_scalars = MagicMock()
        mock_cps_scalars.all.return_value = [cp]
        mock_cps.scalars.return_value = mock_cps_scalars

        db.execute.side_effect = [mock_scalar, mock_class, mock_att, mock_cps]

        csv_str, _ = trip_service.export_attendance_csv(db, trip.id)

        assert "# Check1 : 50%" in csv_str


class TestGenerateExportFilename:
    """Tests pour _generate_export_filename."""

    def test_filename_format(self):
        from app.services.trip_service import _generate_export_filename

        result = _generate_export_filename("Bruges", date(2026, 3, 15))
        assert result.startswith("voyage_Bruges_2026-03-15_")
        # Contient l'heure HH-MM
        parts = result.split("_")
        assert len(parts) == 4

    def test_filename_special_chars(self):
        from app.services.trip_service import _generate_export_filename

        result = _generate_export_filename("Paris/Nord", date(2026, 1, 1))
        assert "/" not in result
        assert "Paris-Nord" in result


# ============================================================
# Tests ROUTER — GET /api/v1/trips/{trip_id}/export
# ============================================================


def test_export_single_csv_200(client):
    """Export CSV d'un voyage → 200 avec content-type CSV."""
    trip_id = uuid.uuid4()
    trip = _make_trip(trip_id=trip_id)

    with patch("app.routers.trips.trip_service.export_attendance_csv") as mock_export, \
         patch("app.routers.trips.trip_service._generate_export_filename") as mock_fn:
        mock_export.return_value = ("csv_content", trip)
        mock_fn.return_value = "voyage_Bruges_2026-03-15_10-00"

        response = client.get(f"/api/v1/trips/{trip_id}/export")

    assert response.status_code == 200
    assert "text/csv" in response.headers["content-type"]
    assert "voyage_Bruges_2026-03-15_10-00.csv" in response.headers["content-disposition"]
    assert response.text == "csv_content"


def test_export_single_zip_with_password(client):
    """Export avec password → 200 ZIP."""
    trip_id = uuid.uuid4()
    trip = _make_trip(trip_id=trip_id)

    with patch("app.routers.trips.trip_service.export_attendance_csv") as mock_export, \
         patch("app.routers.trips.trip_service._generate_export_filename") as mock_fn:
        mock_export.return_value = ("csv_content", trip)
        mock_fn.return_value = "voyage_Bruges_2026-03-15_10-00"

        response = client.get(f"/api/v1/trips/{trip_id}/export?password=secret123")

    assert response.status_code == 200
    assert "application/zip" in response.headers["content-type"]


def test_export_single_404(client):
    """Trip introuvable → 404."""
    trip_id = uuid.uuid4()

    with patch("app.routers.trips.trip_service.export_attendance_csv") as mock_export:
        mock_export.side_effect = ValueError("Voyage introuvable.")

        response = client.get(f"/api/v1/trips/{trip_id}/export")

    assert response.status_code == 404


def test_export_single_403_teacher(client):
    """Role TEACHER → 403 sur export."""
    from app.dependencies import get_current_user
    from app.main import app
    from app.models.user import User

    teacher = MagicMock(spec=User)
    teacher.id = uuid.uuid4()
    teacher.role = "TEACHER"
    teacher.email = "t@schooltrack.be"
    teacher.is_2fa_enabled = False
    teacher.totp_secret = None

    app.dependency_overrides[get_current_user] = lambda: teacher

    trip_id = uuid.uuid4()
    response = client.get(f"/api/v1/trips/{trip_id}/export")

    assert response.status_code == 403


# ============================================================
# Tests ROUTER — GET /api/v1/trips/export-all
# ============================================================


def test_export_all_200(client):
    """Export multi-voyages ZIP → 200."""
    t1 = _make_trip(destination="Bruges")
    t2 = _make_trip(destination="Anvers")

    with patch("app.routers.trips.trip_service.export_attendance_csv") as mock_export, \
         patch("app.routers.trips.trip_service._generate_export_filename") as mock_fn:
        mock_export.side_effect = [
            ("csv1", t1),
            ("csv2", t2),
        ]
        mock_fn.side_effect = ["voyage_Bruges_2026-03-15_10-00", "voyage_Anvers_2026-03-15_10-00"]

        response = client.get(
            f"/api/v1/trips/export-all?trip_ids={t1.id},{t2.id}"
        )

    assert response.status_code == 200
    assert "application/zip" in response.headers["content-type"]

    # Verifier que le ZIP contient 2 fichiers
    z = zipfile.ZipFile(io.BytesIO(response.content))
    assert len(z.namelist()) == 2


def test_export_all_400_empty_ids(client):
    """Aucun ID → 400."""
    response = client.get("/api/v1/trips/export-all?trip_ids=")
    assert response.status_code == 400


def test_export_all_400_invalid_uuid(client):
    """UUID invalide → 400."""
    response = client.get("/api/v1/trips/export-all?trip_ids=not-a-uuid")
    assert response.status_code == 400
    assert "invalide" in response.json()["detail"].lower()


def test_export_all_404_trip_not_found(client):
    """Un des voyages introuvable → 404."""
    tid = uuid.uuid4()

    with patch("app.routers.trips.trip_service.export_attendance_csv") as mock_export:
        mock_export.side_effect = ValueError("Voyage introuvable.")

        response = client.get(f"/api/v1/trips/export-all?trip_ids={tid}")

    assert response.status_code == 404
