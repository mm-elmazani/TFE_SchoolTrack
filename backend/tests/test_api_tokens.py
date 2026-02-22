"""
Tests d'intégration API pour les assignations de bracelets (US 1.5).
"""

import uuid
from datetime import datetime
from unittest.mock import patch

from app.schemas.assignment import (
    AssignmentResponse,
    TripAssignmentStatus,
    TripStudentWithAssignment,
    TripStudentsResponse,
)


# --- Helper ---

def make_assignment_response(**kwargs) -> AssignmentResponse:
    return AssignmentResponse(
        id=kwargs.get("id", 1),
        token_uid=kwargs.get("token_uid", "ST-001"),
        student_id=kwargs.get("student_id", uuid.uuid4()),
        trip_id=kwargs.get("trip_id", uuid.uuid4()),
        assignment_type=kwargs.get("assignment_type", "NFC_PHYSICAL"),
        assigned_at=datetime.now(),
        released_at=None,
    )


def make_status(trip_id=None, total=10, assigned=5) -> TripAssignmentStatus:
    tid = trip_id or uuid.uuid4()
    return TripAssignmentStatus(
        trip_id=tid,
        total_students=total,
        assigned_students=assigned,
        unassigned_students=total - assigned,
        assignments=[make_assignment_response(trip_id=tid) for _ in range(assigned)],
    )


# ============================================================
# POST /api/v1/tokens/assign
# ============================================================

def test_assign_succes(client):
    """Assignation valide → 201 avec les données de l'assignation."""
    with patch("app.routers.tokens.assignment_service.assign_token") as mock:
        mock.return_value = make_assignment_response()

        response = client.post("/api/v1/tokens/assign", json={
            "token_uid": "ST-001",
            "student_id": str(uuid.uuid4()),
            "trip_id": str(uuid.uuid4()),
            "assignment_type": "NFC_PHYSICAL",
        })

    assert response.status_code == 201
    assert response.json()["token_uid"] == "ST-001"
    assert response.json()["assignment_type"] == "NFC_PHYSICAL"


def test_assign_type_invalide(client):
    """Type d'assignation invalide → 422."""
    response = client.post("/api/v1/tokens/assign", json={
        "token_uid": "ST-001",
        "student_id": str(uuid.uuid4()),
        "trip_id": str(uuid.uuid4()),
        "assignment_type": "BLUETOOTH",
    })
    assert response.status_code == 422


def test_assign_token_uid_vide(client):
    """UID vide → 422."""
    response = client.post("/api/v1/tokens/assign", json={
        "token_uid": "   ",
        "student_id": str(uuid.uuid4()),
        "trip_id": str(uuid.uuid4()),
        "assignment_type": "NFC_PHYSICAL",
    })
    assert response.status_code == 422


def test_assign_conflit_token_deja_pris(client):
    """Token déjà assigné → 409."""
    with patch("app.routers.tokens.assignment_service.assign_token") as mock:
        mock.side_effect = ValueError("Le bracelet 'ST-001' est déjà assigné sur ce voyage.")

        response = client.post("/api/v1/tokens/assign", json={
            "token_uid": "ST-001",
            "student_id": str(uuid.uuid4()),
            "trip_id": str(uuid.uuid4()),
            "assignment_type": "NFC_PHYSICAL",
        })

    assert response.status_code == 409
    assert "ST-001" in response.json()["detail"]


def test_assign_eleve_non_inscrit(client):
    """Élève non inscrit au voyage → 409."""
    with patch("app.routers.tokens.assignment_service.assign_token") as mock:
        mock.side_effect = ValueError("Cet élève n'est pas inscrit à ce voyage.")

        response = client.post("/api/v1/tokens/assign", json={
            "token_uid": "ST-002",
            "student_id": str(uuid.uuid4()),
            "trip_id": str(uuid.uuid4()),
            "assignment_type": "QR_PHYSICAL",
        })

    assert response.status_code == 409


def test_assign_body_manquant(client):
    """Requête sans body → 422."""
    response = client.post("/api/v1/tokens/assign")
    assert response.status_code == 422


# ============================================================
# POST /api/v1/tokens/reassign
# ============================================================

def test_reassign_succes(client):
    """Réassignation valide → 201."""
    with patch("app.routers.tokens.assignment_service.reassign_token") as mock:
        mock.return_value = make_assignment_response(token_uid="ST-002")

        response = client.post("/api/v1/tokens/reassign", json={
            "token_uid": "ST-002",
            "student_id": str(uuid.uuid4()),
            "trip_id": str(uuid.uuid4()),
            "assignment_type": "NFC_PHYSICAL",
            "justification": "Bracelet endommagé",
        })

    assert response.status_code == 201
    assert response.json()["token_uid"] == "ST-002"


def test_reassign_sans_justification(client):
    """Réassignation sans justification → 422."""
    response = client.post("/api/v1/tokens/reassign", json={
        "token_uid": "ST-001",
        "student_id": str(uuid.uuid4()),
        "trip_id": str(uuid.uuid4()),
        "assignment_type": "NFC_PHYSICAL",
        "justification": "   ",
    })
    assert response.status_code == 422


# ============================================================
# GET /api/v1/trips/{trip_id}/assignments
# ============================================================

def test_get_assignments_status(client):
    """Statut des assignations → 200 avec compteurs corrects."""
    trip_id = uuid.uuid4()
    with patch("app.routers.tokens.assignment_service.get_trip_assignment_status") as mock:
        mock.return_value = make_status(trip_id=trip_id, total=30, assigned=12)

        response = client.get(f"/api/v1/trips/{trip_id}/assignments")

    assert response.status_code == 200
    assert response.json()["total_students"] == 30
    assert response.json()["assigned_students"] == 12
    assert response.json()["unassigned_students"] == 18
    assert len(response.json()["assignments"]) == 12


def test_get_assignments_uuid_invalide(client):
    """UUID malformé → 422."""
    response = client.get("/api/v1/trips/pas-un-uuid/assignments")
    assert response.status_code == 422


# ============================================================
# GET /api/v1/trips/{trip_id}/assignments/export
# ============================================================

def test_export_csv(client):
    """Export CSV → 200 avec Content-Disposition."""
    trip_id = uuid.uuid4()
    with patch("app.routers.tokens.assignment_service.export_assignments_csv") as mock:
        mock.return_value = "token_uid;student_id;assignment_type;assigned_at\nST-001;abc;NFC_PHYSICAL;2026-02-20\n"

        response = client.get(f"/api/v1/trips/{trip_id}/assignments/export")

    assert response.status_code == 200
    assert "text/csv" in response.headers["content-type"]
    assert "attachment" in response.headers["content-disposition"]
    assert "ST-001" in response.text


# ============================================================
# GET /api/v1/trips/{trip_id}/students
# ============================================================

def make_trip_students_response(trip_id=None, total=10, assigned=5) -> TripStudentsResponse:
    """Construit une TripStudentsResponse pour les tests."""
    tid = trip_id or uuid.uuid4()
    students = [
        TripStudentWithAssignment(
            id=uuid.uuid4(),
            first_name=f"Prénom{i}",
            last_name=f"Nom{i}",
            email=f"eleve{i}@test.be",
            token_uid=f"ST-{i:03d}" if i < assigned else None,
            assignment_type="NFC_PHYSICAL" if i < assigned else None,
            assigned_at=datetime.now() if i < assigned else None,
        )
        for i in range(total)
    ]
    return TripStudentsResponse(
        trip_id=tid,
        total=total,
        assigned=assigned,
        unassigned=total - assigned,
        students=students,
    )


def test_get_trip_students_succes(client):
    """Liste élèves + assignations → 200 avec compteurs corrects."""
    trip_id = uuid.uuid4()
    with patch(
        "app.routers.tokens.assignment_service.get_trip_students_with_assignments"
    ) as mock:
        mock.return_value = make_trip_students_response(trip_id=trip_id, total=10, assigned=5)

        response = client.get(f"/api/v1/trips/{trip_id}/students")

    assert response.status_code == 200
    data = response.json()
    assert data["total"] == 10
    assert data["assigned"] == 5
    assert data["unassigned"] == 5
    assert len(data["students"]) == 10


def test_get_trip_students_statuts_assignation(client):
    """Les élèves assignés ont un token_uid non null, les autres null."""
    trip_id = uuid.uuid4()
    with patch(
        "app.routers.tokens.assignment_service.get_trip_students_with_assignments"
    ) as mock:
        mock.return_value = make_trip_students_response(trip_id=trip_id, total=3, assigned=1)

        response = client.get(f"/api/v1/trips/{trip_id}/students")

    assert response.status_code == 200
    students = response.json()["students"]
    assigned = [s for s in students if s["token_uid"] is not None]
    unassigned = [s for s in students if s["token_uid"] is None]
    assert len(assigned) == 1
    assert len(unassigned) == 2
    assert assigned[0]["assignment_type"] == "NFC_PHYSICAL"


def test_get_trip_students_uuid_invalide(client):
    """UUID malformé → 422."""
    response = client.get("/api/v1/trips/pas-un-uuid/students")
    assert response.status_code == 422


# ============================================================
# POST /api/v1/trips/{trip_id}/release-tokens
# ============================================================

def test_release_tokens_succes(client):
    """Libération manuelle → 200 avec trip_id et released_count."""
    trip_id = uuid.uuid4()
    with patch("app.routers.tokens.assignment_service.release_trip_tokens") as mock:
        mock.return_value = 5
        response = client.post(f"/api/v1/trips/{trip_id}/release-tokens")

    assert response.status_code == 200
    assert response.json()["released_count"] == 5
    assert response.json()["trip_id"] == str(trip_id)


def test_release_tokens_voyage_sans_assignation(client):
    """Voyage sans assignation active → 200, released_count = 0."""
    trip_id = uuid.uuid4()
    with patch("app.routers.tokens.assignment_service.release_trip_tokens") as mock:
        mock.return_value = 0
        response = client.post(f"/api/v1/trips/{trip_id}/release-tokens")

    assert response.status_code == 200
    assert response.json()["released_count"] == 0


def test_release_tokens_uuid_invalide(client):
    """UUID malformé → 422."""
    response = client.post("/api/v1/trips/pas-un-uuid/release-tokens")
    assert response.status_code == 422
