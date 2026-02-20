"""
Tests unitaires pour le service de gestion des classes (US 1.3).
"""

import uuid
from unittest.mock import MagicMock, patch

import pytest
from pydantic import ValidationError
from sqlalchemy.exc import IntegrityError

from app.schemas.school_class import ClassCreate, ClassStudentsAssign, ClassTeachersAssign, ClassUpdate
from app.services.class_service import (
    assign_students,
    assign_teachers,
    create_class,
    delete_class,
    get_class,
    remove_student,
    remove_teacher,
    update_class,
)


# --- Helpers ---

def make_class_mock(class_id=None, name="6ème A", year="2025-2026"):
    c = MagicMock()
    c.id = class_id or uuid.uuid4()
    c.name = name
    c.year = year
    c.created_at = MagicMock()
    c.updated_at = MagicMock()
    return c


def make_db_mock(school_class=None, scalar_value=0):
    db = MagicMock()
    db.get.return_value = school_class
    db.execute.return_value.scalars.return_value.all.return_value = []
    db.execute.return_value.scalar.return_value = scalar_value
    return db


# --- Validation des schémas ---

def test_class_create_nom_vide_rejete():
    with pytest.raises(ValidationError):
        ClassCreate(name="   ")


def test_class_create_nom_valide():
    c = ClassCreate(name="  6ème A  ")
    assert c.name == "6ème A"  # strip appliqué


def test_class_students_assign_liste_vide_rejetee():
    with pytest.raises(ValidationError):
        ClassStudentsAssign(student_ids=[])


def test_class_teachers_assign_liste_vide_rejetee():
    with pytest.raises(ValidationError):
        ClassTeachersAssign(teacher_ids=[])


# --- create_class ---

def test_create_class_succes():
    db = make_db_mock()
    with patch("app.services.class_service._to_response") as mock_resp:
        mock_resp.return_value = MagicMock()
        result = create_class(db, ClassCreate(name="TI-BAC3", year="2025-2026"))
        db.add.assert_called_once()
        db.commit.assert_called_once()
        assert result is not None


def test_create_class_nom_duplique():
    db = make_db_mock()
    db.commit.side_effect = IntegrityError("duplicate", None, None)
    with pytest.raises(ValueError, match="existe déjà"):
        create_class(db, ClassCreate(name="6ème A"))


# --- get_class ---

def test_get_class_inexistante():
    db = make_db_mock(school_class=None)
    result = get_class(db, uuid.uuid4())
    assert result is None


def test_get_class_existante():
    c = make_class_mock()
    db = make_db_mock(school_class=c)
    with patch("app.services.class_service._to_response") as mock_resp:
        mock_resp.return_value = MagicMock(id=c.id)
        result = get_class(db, c.id)
        assert result is not None


# --- delete_class ---

def test_delete_class_inexistante():
    db = make_db_mock(school_class=None)
    result = delete_class(db, uuid.uuid4())
    assert result is False
    db.commit.assert_not_called()


def test_delete_class_sans_voyage_actif():
    c = make_class_mock()
    db = make_db_mock(school_class=c, scalar_value=None)  # pas de voyage actif
    result = delete_class(db, c.id)
    assert result is True
    db.delete.assert_called_once_with(c)
    db.commit.assert_called_once()


def test_delete_class_avec_voyage_actif_bloque():
    c = make_class_mock()
    db = make_db_mock(school_class=c, scalar_value=uuid.uuid4())  # voyage actif trouvé
    with pytest.raises(ValueError, match="voyage planifié ou en cours"):
        delete_class(db, c.id)
    db.delete.assert_not_called()


# --- assign_students ---

def test_assign_students_classe_inexistante():
    db = make_db_mock(school_class=None)
    with pytest.raises(ValueError, match="introuvable"):
        assign_students(db, uuid.uuid4(), ClassStudentsAssign(student_ids=[uuid.uuid4()]))


def test_assign_students_ignore_doublons():
    existing_id = uuid.uuid4()
    new_id = uuid.uuid4()
    c = make_class_mock()
    db = make_db_mock(school_class=c)
    db.execute.return_value.scalars.return_value.all.return_value = [existing_id]

    with patch("app.services.class_service._to_response") as mock_resp:
        mock_resp.return_value = MagicMock()
        assign_students(db, c.id, ClassStudentsAssign(student_ids=[existing_id, new_id]))
        # Seulement new_id doit être inséré
        mappings = db.bulk_insert_mappings.call_args[0][1]
        assert len(mappings) == 1
        assert mappings[0]["student_id"] == new_id


# --- remove_student / remove_teacher ---

def test_remove_student_inexistant():
    db = make_db_mock()
    db.get.return_value = None
    result = remove_student(db, uuid.uuid4(), uuid.uuid4())
    assert result is False
    db.commit.assert_not_called()


def test_remove_teacher_existant():
    link = MagicMock()
    db = make_db_mock()
    db.get.return_value = link
    result = remove_teacher(db, uuid.uuid4(), uuid.uuid4())
    assert result is True
    db.delete.assert_called_once_with(link)
    db.commit.assert_called_once()
