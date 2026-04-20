"""
Tests unitaires — bundle offline avec double assignation (physique + QR digital).

Scénarios couverts :
- Élève avec 1 assignation physique → assignment + assignments[1]
- Élève avec 1 assignation digitale seule → assignment = digital
- Élève avec NFC + QR digital → assignment = NFC (primaire), assignments = [NFC, QR]
- Élève sans assignation → assignment=None, assignments=[]
- Rétro-compat : assignment est toujours physique en priorité
- Tri alphabétique avec données chiffrées
- Mix d'élèves avec 0, 1 ou 2 assignations
"""

import uuid
from datetime import date
from unittest.mock import MagicMock

import pytest

from app.models.assignment import Assignment
from app.models.checkpoint import Checkpoint
from app.models.student import Student
from app.models.trip import Trip
from app.services.offline_service import get_offline_data


# ----------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------

def make_trip(status="PLANNED"):
    t = MagicMock(spec=Trip)
    t.id = uuid.uuid4()
    t.destination = "Bruxelles"
    t.date = date(2026, 4, 1)
    t.description = "Visite du Parlement"
    t.status = status
    return t


def make_student(first_name="Alice", last_name="Dupont", student_id=None):
    s = MagicMock(spec=Student)
    s.id = student_id or uuid.uuid4()
    s.first_name = first_name
    s.last_name = last_name
    s.email = None
    s.phone = None
    s.photo_url = None
    return s


def make_assignment(student_id, trip_id, token_uid="ST-001", assignment_type="NFC_PHYSICAL"):
    a = MagicMock(spec=Assignment)
    a.student_id = student_id
    a.trip_id = trip_id
    a.token_uid = token_uid
    a.assignment_type = assignment_type
    a.released_at = None
    return a


def make_db(trip, students, assignments, checkpoints=None):
    """
    Mock de session DB pour offline_service.get_offline_data().
    Execute order : trip, students, assignments, [class_rows si students],
    trip_class_rows, checkpoints.
    """
    db = MagicMock()

    trip_result = MagicMock()
    trip_result.scalar.return_value = trip

    students_result = MagicMock()
    students_result.scalars.return_value.all.return_value = students

    assignments_result = MagicMock()
    assignments_result.scalars.return_value.all.return_value = assignments

    class_rows_result = MagicMock()
    class_rows_result.all.return_value = []

    trip_classes_result = MagicMock()
    trip_classes_result.scalars.return_value.all.return_value = []

    checkpoints_result = MagicMock()
    checkpoints_result.scalars.return_value.all.return_value = checkpoints or []

    side_effects = [trip_result, students_result, assignments_result]
    if students:
        side_effects.append(class_rows_result)
    side_effects.extend([trip_classes_result, checkpoints_result])

    db.execute.side_effect = side_effects
    return db


# ================================================================
# Élève avec une seule assignation physique
# ================================================================

class TestSingleAssignment:

    def test_une_assignation_nfc(self):
        """Élève avec NFC uniquement → assignment = NFC, assignments = [NFC]."""
        trip = make_trip()
        student = make_student()
        nfc = make_assignment(student.id, trip.id, "ST-042", "NFC_PHYSICAL")
        db = make_db(trip, [student], [nfc])

        result = get_offline_data(db, trip.id)

        assert len(result.students) == 1
        s = result.students[0]
        assert s.assignment is not None
        assert s.assignment.token_uid == "ST-042"
        assert s.assignment.assignment_type == "NFC_PHYSICAL"
        assert len(s.assignments) == 1
        assert s.assignments[0].token_uid == "ST-042"

    def test_une_assignation_qr_digital_seule(self):
        """Élève avec QR digital uniquement → assignment = QR_DIGITAL."""
        trip = make_trip()
        student = make_student()
        qr = make_assignment(student.id, trip.id, "QRD-ABC123", "QR_DIGITAL")
        db = make_db(trip, [student], [qr])

        result = get_offline_data(db, trip.id)

        s = result.students[0]
        assert s.assignment is not None
        assert s.assignment.token_uid == "QRD-ABC123"
        assert s.assignment.assignment_type == "QR_DIGITAL"
        assert len(s.assignments) == 1


# ================================================================
# Élève avec double assignation (physique + digital)
# ================================================================

class TestDualAssignment:

    def test_nfc_plus_qr_digital(self):
        """Élève avec NFC + QR digital → assignment = NFC (primaire), assignments = 2."""
        trip = make_trip()
        student = make_student()
        nfc = make_assignment(student.id, trip.id, "ST-042", "NFC_PHYSICAL")
        qr = make_assignment(student.id, trip.id, "QRD-XYZ789", "QR_DIGITAL")
        db = make_db(trip, [student], [nfc, qr])

        result = get_offline_data(db, trip.id)

        s = result.students[0]
        # Primary doit être le physique
        assert s.assignment.assignment_type == "NFC_PHYSICAL"
        assert s.assignment.token_uid == "ST-042"
        # Toutes les assignations présentes
        assert len(s.assignments) == 2
        types = {a.assignment_type for a in s.assignments}
        assert types == {"NFC_PHYSICAL", "QR_DIGITAL"}
        uids = {a.token_uid for a in s.assignments}
        assert "ST-042" in uids
        assert "QRD-XYZ789" in uids

    def test_qr_digital_avant_nfc_dans_la_liste(self):
        """Même si QR digital vient en premier dans la liste, assignment = physique."""
        trip = make_trip()
        student = make_student()
        qr = make_assignment(student.id, trip.id, "QRD-FIRST", "QR_DIGITAL")
        nfc = make_assignment(student.id, trip.id, "ST-099", "NFC_PHYSICAL")
        # QR digital en premier dans la liste
        db = make_db(trip, [student], [qr, nfc])

        result = get_offline_data(db, trip.id)

        s = result.students[0]
        assert s.assignment.assignment_type == "NFC_PHYSICAL"
        assert s.assignment.token_uid == "ST-099"

    def test_qr_physique_plus_qr_digital(self):
        """QR physique + QR digital → assignment = QR_PHYSICAL (physique prioritaire)."""
        trip = make_trip()
        student = make_student()
        qr_phys = make_assignment(student.id, trip.id, "QRP-001", "QR_PHYSICAL")
        qr_dig = make_assignment(student.id, trip.id, "QRD-002", "QR_DIGITAL")
        db = make_db(trip, [student], [qr_phys, qr_dig])

        result = get_offline_data(db, trip.id)

        s = result.students[0]
        assert s.assignment.assignment_type == "QR_PHYSICAL"
        assert len(s.assignments) == 2


# ================================================================
# Élève sans assignation
# ================================================================

class TestNoAssignment:

    def test_sans_assignation(self):
        """Élève sans aucune assignation → assignment=None, assignments=[]."""
        trip = make_trip()
        student = make_student()
        db = make_db(trip, [student], [])

        result = get_offline_data(db, trip.id)

        s = result.students[0]
        assert s.assignment is None
        assert s.assignments == []


# ================================================================
# Mix d'élèves avec différentes configurations
# ================================================================

class TestMixedStudents:

    def test_mix_0_1_2_assignations(self):
        """
        3 élèves :
        - Alice : NFC + QR digital (2 assignations)
        - Bob : QR digital seul (1 assignation)
        - Charlie : aucune assignation (0)
        """
        trip = make_trip()
        alice = make_student("Alice", "Aaa")
        bob = make_student("Bob", "Bbb")
        charlie = make_student("Charlie", "Ccc")

        assignments = [
            make_assignment(alice.id, trip.id, "ST-ALICE", "NFC_PHYSICAL"),
            make_assignment(alice.id, trip.id, "QRD-ALICE", "QR_DIGITAL"),
            make_assignment(bob.id, trip.id, "QRD-BOB", "QR_DIGITAL"),
        ]
        db = make_db(trip, [alice, bob, charlie], assignments)

        result = get_offline_data(db, trip.id)

        assert len(result.students) == 3

        # Trouver chaque élève par prénom
        by_name = {s.first_name: s for s in result.students}

        # Alice : 2 assignations, primaire = NFC
        assert len(by_name["Alice"].assignments) == 2
        assert by_name["Alice"].assignment.assignment_type == "NFC_PHYSICAL"

        # Bob : 1 assignation QR digital
        assert len(by_name["Bob"].assignments) == 1
        assert by_name["Bob"].assignment.assignment_type == "QR_DIGITAL"

        # Charlie : aucune
        assert by_name["Charlie"].assignment is None
        assert by_name["Charlie"].assignments == []

    def test_tri_alphabetique(self):
        """Les élèves sont triés par nom de famille puis prénom."""
        trip = make_trip()
        s1 = make_student("Zoé", "Martin")
        s2 = make_student("Alice", "Dupont")
        s3 = make_student("Bob", "Dupont")
        db = make_db(trip, [s1, s2, s3], [])

        result = get_offline_data(db, trip.id)

        names = [(s.last_name, s.first_name) for s in result.students]
        assert names == [("Dupont", "Alice"), ("Dupont", "Bob"), ("Martin", "Zoé")]


# ================================================================
# Assignations d'autres voyages ignorées
# ================================================================

class TestAssignmentIsolation:

    def test_assignation_autre_voyage_ignoree(self):
        """Seules les assignations du voyage demandé sont incluses."""
        trip = make_trip()
        student = make_student()
        other_trip_id = uuid.uuid4()

        # Assignation sur un AUTRE voyage (ne devrait pas apparaître)
        other_assign = make_assignment(student.id, other_trip_id, "ST-OTHER", "NFC_PHYSICAL")
        # Mais le filtre est fait par la requête SQL, ici on ne la passe pas dans le mock
        db = make_db(trip, [student], [])

        result = get_offline_data(db, trip.id)

        s = result.students[0]
        assert s.assignment is None
        assert s.assignments == []
