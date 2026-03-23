"""
Tests unitaires pour le service d'assignation de bracelets (US 1.5).

Scénarios couverts :
- Validation schemas Pydantic (types, token_uid vide, justification)
- _is_physical : helper de catégorisation
- assign_token : élève non inscrit, token déjà pris, orphan cleanup,
  même catégorie bloquée (physique+physique, digital+digital),
  double assignation cross-catégorie autorisée (physique+digital, digital+physique)
- reassign_token : libère uniquement la même catégorie,
  conserve l'assignation cross-catégorie, libère l'ancien token
- get_trip_students_with_assignments : mapping primaire/secondaire,
  compteurs assigned/unassigned/assigned_digital, tri alphabétique
- release_assignment : libération individuelle, introuvable, déjà libérée
- release_trip_tokens : libération en masse
"""

import uuid
from datetime import datetime
from unittest.mock import MagicMock, patch

import pytest
from pydantic import ValidationError

from app.models.assignment import Assignment, Token
from app.models.student import Student
from app.models.trip import Trip, TripStudent
from app.schemas.assignment import AssignmentCreate, AssignmentReassign
from app.services.assignment_service import (
    PHYSICAL_TYPES,
    _is_physical,
    assign_token,
    get_trip_students_with_assignments,
    reassign_token,
    release_assignment,
    release_trip_tokens,
)


# ----------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------

def _uid():
    return uuid.uuid4()


def _scalar_result(value):
    """Mock d'un résultat db.execute() avec .scalar() prédéfini."""
    m = MagicMock()
    m.scalar.return_value = value
    return m


def _scalars_result(values):
    """Mock d'un résultat db.execute() avec .scalars().all() prédéfini."""
    m = MagicMock()
    m.scalars.return_value.all.return_value = values
    return m


def make_assignment_mock(
    id=1,
    token_uid="ST-001",
    student_id=None,
    trip_id=None,
    assignment_type="NFC_PHYSICAL",
    released_at=None,
    assigned_at=None,
):
    a = MagicMock(spec=Assignment)
    a.id = id
    a.token_uid = token_uid
    a.student_id = student_id or _uid()
    a.trip_id = trip_id or _uid()
    a.assignment_type = assignment_type
    a.released_at = released_at
    a.assigned_at = assigned_at or datetime(2026, 3, 20, 10, 0, 0)
    a.assigned_by = None
    return a


def make_student_mock(first_name="Alice", last_name="Dupont", email="alice@schooltrack.be"):
    s = MagicMock(spec=Student)
    s.id = _uid()
    s.first_name = first_name
    s.last_name = last_name
    s.email = email
    return s


def _mock_refresh(obj):
    """Simule db.refresh() en ajoutant les champs auto-générés par la BDD."""
    if isinstance(obj, Assignment):
        if obj.id is None:
            obj.id = 1
        if obj.assigned_at is None:
            obj.assigned_at = datetime(2026, 3, 20, 10, 0, 0)


# ================================================================
# Validation des schémas Pydantic
# ================================================================

def test_assignment_type_invalide():
    with pytest.raises(ValidationError, match="Type invalide"):
        AssignmentCreate(
            token_uid="ST-001",
            student_id=_uid(),
            trip_id=_uid(),
            assignment_type="BLUETOOTH",
        )


def test_assignment_token_uid_vide():
    with pytest.raises(ValidationError):
        AssignmentCreate(
            token_uid="   ",
            student_id=_uid(),
            trip_id=_uid(),
            assignment_type="NFC_PHYSICAL",
        )


def test_assignment_token_uid_uppercase():
    """Le token_uid doit être mis en majuscules automatiquement."""
    data = AssignmentCreate(
        token_uid="st-001",
        student_id=_uid(),
        trip_id=_uid(),
        assignment_type="NFC_PHYSICAL",
    )
    assert data.token_uid == "ST-001"


def test_reassign_sans_justification():
    with pytest.raises(ValidationError, match="justification"):
        AssignmentReassign(
            token_uid="ST-001",
            student_id=_uid(),
            trip_id=_uid(),
            assignment_type="NFC_PHYSICAL",
            justification="   ",
        )


def test_reassign_types_valides():
    for t in ("NFC_PHYSICAL", "QR_PHYSICAL", "QR_DIGITAL"):
        data = AssignmentReassign(
            token_uid="ST-001",
            student_id=_uid(),
            trip_id=_uid(),
            assignment_type=t,
            justification="Bracelet endommagé",
        )
        assert data.assignment_type == t


# ================================================================
# _is_physical
# ================================================================

class TestIsPhysical:

    def test_nfc_est_physique(self):
        assert _is_physical("NFC_PHYSICAL") is True

    def test_qr_physical_est_physique(self):
        assert _is_physical("QR_PHYSICAL") is True

    def test_qr_digital_pas_physique(self):
        assert _is_physical("QR_DIGITAL") is False

    def test_type_inconnu_pas_physique(self):
        assert _is_physical("UNKNOWN") is False

    def test_constante_physical_types(self):
        assert PHYSICAL_TYPES == {"NFC_PHYSICAL", "QR_PHYSICAL"}


# ================================================================
# assign_token — validations et catégories
# ================================================================

class TestAssignToken:

    def test_eleve_non_inscrit_au_voyage(self):
        """Élève non inscrit au voyage → ValueError."""
        db = MagicMock()
        db.execute.side_effect = [_scalar_result(None)]  # is_participant → None

        data = AssignmentCreate(
            token_uid="ST-001", student_id=_uid(),
            trip_id=_uid(), assignment_type="NFC_PHYSICAL",
        )
        with pytest.raises(ValueError, match="pas inscrit"):
            assign_token(db, data)

    def test_token_deja_assigne_meme_voyage(self):
        """Token déjà assigné sur ce voyage (pas orphelin) → ValueError."""
        db = MagicMock()
        trip_id = _uid()
        existing = make_assignment_mock(student_id=_uid(), trip_id=trip_id)
        trip_student = MagicMock(spec=TripStudent)

        db.execute.side_effect = [
            _scalar_result(trip_student),   # is_participant → OK
            _scalar_result(existing),       # token_taken → existant
            _scalar_result(trip_student),   # still_enrolled → oui (pas orphelin)
        ]

        data = AssignmentCreate(
            token_uid="ST-001", student_id=_uid(),
            trip_id=trip_id, assignment_type="NFC_PHYSICAL",
        )
        with pytest.raises(ValueError, match="deja assigne"):
            assign_token(db, data)

    def test_token_orphelin_libere_automatiquement(self):
        """Token assigné à un élève retiré du voyage → assignation orpheline libérée."""
        db = MagicMock()
        db.refresh.side_effect = _mock_refresh
        trip_id = _uid()
        orphan = make_assignment_mock(token_uid="ST-001", trip_id=trip_id)

        db.execute.side_effect = [
            _scalar_result(MagicMock(spec=TripStudent)),  # is_participant
            _scalar_result(orphan),                        # token_taken → orphan
            _scalar_result(None),                          # still_enrolled → non
            _scalars_result([]),                            # student_assignments → vide
        ]

        data = AssignmentCreate(
            token_uid="ST-001", student_id=_uid(),
            trip_id=trip_id, assignment_type="NFC_PHYSICAL",
        )
        with patch("app.services.assignment_service._update_token_status"):
            assign_token(db, data)

        # L'orphelin doit avoir été libéré
        assert orphan.released_at is not None
        db.add.assert_called_once()

    def test_meme_categorie_physique_bloquee(self):
        """Élève a déjà un NFC → assigner un QR_PHYSICAL → ValueError (même catégorie physique)."""
        db = MagicMock()
        student_id = _uid()
        trip_id = _uid()

        existing_nfc = make_assignment_mock(
            student_id=student_id, trip_id=trip_id, assignment_type="NFC_PHYSICAL",
        )

        db.execute.side_effect = [
            _scalar_result(MagicMock(spec=TripStudent)),
            _scalar_result(None),                          # token libre
            _scalars_result([existing_nfc]),                # déjà un physique
        ]

        data = AssignmentCreate(
            token_uid="QR-099", student_id=student_id,
            trip_id=trip_id, assignment_type="QR_PHYSICAL",
        )
        with pytest.raises(ValueError, match="physique"):
            assign_token(db, data)

    def test_meme_categorie_digitale_bloquee(self):
        """Élève a déjà un QR_DIGITAL → assigner un 2e QR_DIGITAL → ValueError."""
        db = MagicMock()
        student_id = _uid()
        trip_id = _uid()

        existing_digital = make_assignment_mock(
            student_id=student_id, trip_id=trip_id, assignment_type="QR_DIGITAL",
        )

        db.execute.side_effect = [
            _scalar_result(MagicMock(spec=TripStudent)),
            _scalar_result(None),
            _scalars_result([existing_digital]),
        ]

        data = AssignmentCreate(
            token_uid="QRD-XYZ", student_id=student_id,
            trip_id=trip_id, assignment_type="QR_DIGITAL",
        )
        with pytest.raises(ValueError, match="digital"):
            assign_token(db, data)

    def test_physique_plus_digital_autorise(self):
        """Élève a un NFC → assigner un QR_DIGITAL → autorisé (catégories différentes)."""
        db = MagicMock()
        db.refresh.side_effect = _mock_refresh
        student_id = _uid()
        trip_id = _uid()

        existing_nfc = make_assignment_mock(
            student_id=student_id, trip_id=trip_id, assignment_type="NFC_PHYSICAL",
        )

        db.execute.side_effect = [
            _scalar_result(MagicMock(spec=TripStudent)),
            _scalar_result(None),
            _scalars_result([existing_nfc]),  # physique existe, mais on assigne digital
        ]

        data = AssignmentCreate(
            token_uid="QRD-NEW", student_id=student_id,
            trip_id=trip_id, assignment_type="QR_DIGITAL",
        )
        with patch("app.services.assignment_service._update_token_status"):
            assign_token(db, data)

        db.add.assert_called_once()
        db.commit.assert_called_once()

    def test_digital_plus_physique_autorise(self):
        """Élève a un QR_DIGITAL → assigner un NFC → autorisé (catégories différentes)."""
        db = MagicMock()
        db.refresh.side_effect = _mock_refresh
        student_id = _uid()
        trip_id = _uid()

        existing_digital = make_assignment_mock(
            student_id=student_id, trip_id=trip_id, assignment_type="QR_DIGITAL",
        )

        db.execute.side_effect = [
            _scalar_result(MagicMock(spec=TripStudent)),
            _scalar_result(None),
            _scalars_result([existing_digital]),
        ]

        data = AssignmentCreate(
            token_uid="ST-042", student_id=student_id,
            trip_id=trip_id, assignment_type="NFC_PHYSICAL",
        )
        with patch("app.services.assignment_service._update_token_status"):
            assign_token(db, data)

        db.add.assert_called_once()

    def test_assign_succes_sans_assignation_existante(self):
        """Assignation valide sans conflit → créée et committée."""
        db = MagicMock()
        db.refresh.side_effect = _mock_refresh

        db.execute.side_effect = [
            _scalar_result(MagicMock(spec=TripStudent)),  # participant
            _scalar_result(None),                          # token libre
            _scalars_result([]),                            # pas d'assignation existante
        ]

        data = AssignmentCreate(
            token_uid="ST-NEW", student_id=_uid(),
            trip_id=_uid(), assignment_type="NFC_PHYSICAL",
        )
        with patch("app.services.assignment_service._update_token_status"):
            assign_token(db, data)

        db.add.assert_called_once()
        added = db.add.call_args[0][0]
        assert isinstance(added, Assignment)
        assert added.token_uid == "ST-NEW"
        assert added.assignment_type == "NFC_PHYSICAL"
        db.commit.assert_called_once()


# ================================================================
# reassign_token — libération par catégorie
# ================================================================

class TestReassignToken:

    def test_reassign_physique_libere_ancien_physique_conserve_digital(self):
        """Réassigner un NFC → l'ancien NFC est libéré, le QR_DIGITAL reste intact."""
        db = MagicMock()
        db.refresh.side_effect = _mock_refresh
        student_id = _uid()
        trip_id = _uid()

        old_nfc = make_assignment_mock(
            id=1, token_uid="ST-OLD", student_id=student_id,
            trip_id=trip_id, assignment_type="NFC_PHYSICAL",
        )
        old_nfc.released_at = None
        existing_digital = make_assignment_mock(
            id=2, token_uid="QRD-ABC", student_id=student_id,
            trip_id=trip_id, assignment_type="QR_DIGITAL",
        )
        existing_digital.released_at = None

        db.execute.side_effect = [
            _scalar_result(None),                              # old_token (ST-NEW pas encore pris)
            _scalars_result([old_nfc, existing_digital]),       # old_student_assignments
        ]

        data = AssignmentReassign(
            token_uid="ST-NEW", student_id=student_id,
            trip_id=trip_id, assignment_type="NFC_PHYSICAL",
            justification="Bracelet perdu",
        )
        with patch("app.services.assignment_service._update_token_status"):
            reassign_token(db, data)

        assert old_nfc.released_at is not None
        assert existing_digital.released_at is None  # digital conservé
        db.flush.assert_called_once()
        db.add.assert_called_once()

    def test_reassign_digital_libere_ancien_digital_conserve_physique(self):
        """Réassigner un QR_DIGITAL → l'ancien digital est libéré, le NFC reste intact."""
        db = MagicMock()
        db.refresh.side_effect = _mock_refresh
        student_id = _uid()
        trip_id = _uid()

        existing_nfc = make_assignment_mock(
            id=1, token_uid="ST-001", student_id=student_id,
            trip_id=trip_id, assignment_type="NFC_PHYSICAL",
        )
        existing_nfc.released_at = None
        old_digital = make_assignment_mock(
            id=2, token_uid="QRD-OLD", student_id=student_id,
            trip_id=trip_id, assignment_type="QR_DIGITAL",
        )
        old_digital.released_at = None

        db.execute.side_effect = [
            _scalar_result(None),
            _scalars_result([existing_nfc, old_digital]),
        ]

        data = AssignmentReassign(
            token_uid="QRD-NEW", student_id=student_id,
            trip_id=trip_id, assignment_type="QR_DIGITAL",
            justification="Nouveau QR demandé",
        )
        with patch("app.services.assignment_service._update_token_status"):
            reassign_token(db, data)

        assert old_digital.released_at is not None
        assert existing_nfc.released_at is None  # physique conservé

    def test_reassign_libere_ancien_token_meme_uid(self):
        """Si le nouveau token_uid est déjà pris par un autre élève, l'ancien est libéré."""
        db = MagicMock()
        db.refresh.side_effect = _mock_refresh
        trip_id = _uid()

        old_token_assign = make_assignment_mock(
            id=10, token_uid="ST-REUSE", student_id=_uid(),
            trip_id=trip_id, assignment_type="NFC_PHYSICAL",
        )
        old_token_assign.released_at = None

        db.execute.side_effect = [
            _scalar_result(old_token_assign),  # old_token → le token est déjà pris
            _scalars_result([]),                 # old_student_assignments → vide
        ]

        data = AssignmentReassign(
            token_uid="ST-REUSE", student_id=_uid(),
            trip_id=trip_id, assignment_type="NFC_PHYSICAL",
            justification="Transfert bracelet",
        )
        with patch("app.services.assignment_service._update_token_status"):
            reassign_token(db, data)

        assert old_token_assign.released_at is not None
        db.flush.assert_called_once()

    def test_reassign_cree_nouvelle_assignation(self):
        """La réassignation crée toujours une nouvelle assignation."""
        db = MagicMock()
        db.refresh.side_effect = _mock_refresh

        db.execute.side_effect = [
            _scalar_result(None),
            _scalars_result([]),
        ]

        data = AssignmentReassign(
            token_uid="ST-FRESH", student_id=_uid(),
            trip_id=_uid(), assignment_type="NFC_PHYSICAL",
            justification="Nouveau bracelet",
        )
        with patch("app.services.assignment_service._update_token_status"):
            reassign_token(db, data)

        db.add.assert_called_once()
        added = db.add.call_args[0][0]
        assert isinstance(added, Assignment)
        assert added.token_uid == "ST-FRESH"

    def test_reassign_sans_ancienne_assignation(self):
        """La réassignation réussit même sans aucune assignation précédente."""
        db = MagicMock()
        db.refresh.side_effect = _mock_refresh

        db.execute.side_effect = [
            _scalar_result(None),
            _scalars_result([]),
        ]

        data = AssignmentReassign(
            token_uid="ST-002", student_id=_uid(),
            trip_id=_uid(), assignment_type="NFC_PHYSICAL",
            justification="Bracelet endommagé",
        )
        with patch("app.services.assignment_service._update_token_status"):
            reassign_token(db, data)

        db.flush.assert_called_once()
        db.add.assert_called_once()
        db.commit.assert_called_once()


# ================================================================
# get_trip_students_with_assignments — mapping primaire/secondaire
# ================================================================

class TestGetTripStudentsWithAssignments:

    def test_eleve_avec_double_assignation(self):
        """Élève avec NFC + QR_DIGITAL → primary + secondary correctement remplis."""
        db = MagicMock()
        trip_id = _uid()
        student = make_student_mock("Alice", "Dupont")

        nfc = make_assignment_mock(
            id=1, token_uid="ST-001", student_id=student.id,
            trip_id=trip_id, assignment_type="NFC_PHYSICAL",
        )
        qr = make_assignment_mock(
            id=2, token_uid="QRD-ABC", student_id=student.id,
            trip_id=trip_id, assignment_type="QR_DIGITAL",
        )

        db.execute.side_effect = [
            _scalars_result([student]),
            _scalars_result([nfc, qr]),
        ]

        result = get_trip_students_with_assignments(db, trip_id)

        assert result.total == 1
        assert result.assigned == 1
        assert result.assigned_digital == 1
        assert result.unassigned == 0

        s = result.students[0]
        assert s.assignment_type == "NFC_PHYSICAL"
        assert s.token_uid == "ST-001"
        assert s.secondary_assignment_type == "QR_DIGITAL"
        assert s.secondary_token_uid == "QRD-ABC"

    def test_eleve_physique_seul(self):
        """Élève avec NFC seulement → secondary = None."""
        db = MagicMock()
        trip_id = _uid()
        student = make_student_mock()

        nfc = make_assignment_mock(
            id=1, token_uid="ST-010", student_id=student.id,
            trip_id=trip_id, assignment_type="NFC_PHYSICAL",
        )

        db.execute.side_effect = [
            _scalars_result([student]),
            _scalars_result([nfc]),
        ]

        result = get_trip_students_with_assignments(db, trip_id)

        assert result.assigned == 1
        assert result.assigned_digital == 0
        s = result.students[0]
        assert s.token_uid == "ST-010"
        assert s.secondary_token_uid is None

    def test_eleve_digital_seul(self):
        """Élève avec QR_DIGITAL seulement → primary=None, secondary=QR_DIGITAL."""
        db = MagicMock()
        trip_id = _uid()
        student = make_student_mock()

        qr = make_assignment_mock(
            id=1, token_uid="QRD-SOLO", student_id=student.id,
            trip_id=trip_id, assignment_type="QR_DIGITAL",
        )

        db.execute.side_effect = [
            _scalars_result([student]),
            _scalars_result([qr]),
        ]

        result = get_trip_students_with_assignments(db, trip_id)

        assert result.assigned == 0         # pas de physique
        assert result.assigned_digital == 1
        assert result.unassigned == 1       # pas de physique = non assigné
        s = result.students[0]
        assert s.assignment_id is None
        assert s.secondary_assignment_type == "QR_DIGITAL"

    def test_eleve_sans_assignation(self):
        """Élève sans aucune assignation → primary=None, secondary=None."""
        db = MagicMock()
        trip_id = _uid()
        student = make_student_mock()

        db.execute.side_effect = [
            _scalars_result([student]),
            _scalars_result([]),
        ]

        result = get_trip_students_with_assignments(db, trip_id)

        assert result.assigned == 0
        assert result.unassigned == 1
        assert result.assigned_digital == 0
        s = result.students[0]
        assert s.assignment_id is None
        assert s.secondary_assignment_id is None

    def test_compteurs_mix_3_eleves(self):
        """3 élèves : Alice (NFC+QR), Bob (QR_DIGITAL seul), Charlie (rien)."""
        db = MagicMock()
        trip_id = _uid()
        alice = make_student_mock("Alice", "Aaa")
        bob = make_student_mock("Bob", "Bbb")
        charlie = make_student_mock("Charlie", "Ccc")

        assignments = [
            make_assignment_mock(id=1, token_uid="ST-A", student_id=alice.id, trip_id=trip_id, assignment_type="NFC_PHYSICAL"),
            make_assignment_mock(id=2, token_uid="QRD-A", student_id=alice.id, trip_id=trip_id, assignment_type="QR_DIGITAL"),
            make_assignment_mock(id=3, token_uid="QRD-B", student_id=bob.id, trip_id=trip_id, assignment_type="QR_DIGITAL"),
        ]

        db.execute.side_effect = [
            _scalars_result([alice, bob, charlie]),
            _scalars_result(assignments),
        ]

        result = get_trip_students_with_assignments(db, trip_id)

        assert result.total == 3
        assert result.assigned == 1         # seule Alice a un physique
        assert result.unassigned == 2       # Bob et Charlie
        assert result.assigned_digital == 2  # Alice et Bob

    def test_tri_alphabetique(self):
        """Les élèves sont triés par last_name puis first_name."""
        db = MagicMock()
        trip_id = _uid()
        zoe = make_student_mock("Zoé", "Martin")
        alice = make_student_mock("Alice", "Dupont")
        bob = make_student_mock("Bob", "Dupont")

        db.execute.side_effect = [
            _scalars_result([zoe, alice, bob]),
            _scalars_result([]),
        ]

        result = get_trip_students_with_assignments(db, trip_id)

        names = [(s.last_name, s.first_name) for s in result.students]
        assert names == [("Dupont", "Alice"), ("Dupont", "Bob"), ("Martin", "Zoé")]


# ================================================================
# release_assignment — libération individuelle
# ================================================================

class TestReleaseAssignment:

    def test_release_ok(self):
        """Libération d'une assignation existante active."""
        db = MagicMock()
        assignment = make_assignment_mock(id=5, token_uid="ST-005")
        assignment.released_at = None

        student = make_student_mock("Alice", "Dupont")
        trip = MagicMock(spec=Trip)
        trip.destination = "Paris"

        db.execute.return_value.scalar.return_value = assignment
        db.get.side_effect = [student, trip]

        with patch("app.services.assignment_service._update_token_status"):
            result = release_assignment(db, 5)

        assert result["assignment_id"] == 5
        assert result["token_uid"] == "ST-005"
        assert result["student_name"] == "Alice Dupont"
        assert result["trip_name"] == "Paris"
        assert assignment.released_at is not None
        db.commit.assert_called_once()

    def test_release_introuvable(self):
        """Assignation inexistante → ValueError."""
        db = MagicMock()
        db.execute.return_value.scalar.return_value = None

        with pytest.raises(ValueError, match="introuvable"):
            release_assignment(db, 999)

    def test_release_deja_liberee(self):
        """Assignation déjà libérée → ValueError."""
        db = MagicMock()
        assignment = make_assignment_mock(id=5)
        assignment.released_at = datetime(2026, 3, 20)
        db.execute.return_value.scalar.return_value = assignment

        with pytest.raises(ValueError, match="deja liberee"):
            release_assignment(db, 5)


# ================================================================
# release_trip_tokens — libération en masse
# ================================================================

class TestReleaseTripTokens:

    def test_release_toutes_les_assignations(self):
        """Libère toutes les assignations actives d'un voyage."""
        db = MagicMock()
        a1 = make_assignment_mock(id=1, token_uid="ST-001")
        a1.released_at = None
        a2 = make_assignment_mock(id=2, token_uid="ST-002")
        a2.released_at = None

        db.execute.return_value.scalars.return_value.all.return_value = [a1, a2]

        with patch("app.services.assignment_service._update_token_status"):
            count = release_trip_tokens(db, _uid())

        assert count == 2
        assert a1.released_at is not None
        assert a2.released_at is not None
        db.commit.assert_called_once()

    def test_release_aucune_assignation(self):
        """Aucune assignation active → retourne 0 sans commit."""
        db = MagicMock()
        db.execute.return_value.scalars.return_value.all.return_value = []

        count = release_trip_tokens(db, _uid())

        assert count == 0
        db.commit.assert_not_called()
