"""
Service d'import CSV pour les élèves.
Gère le parsing, la validation, la détection de doublons et l'insertion bulk.

Colonne optionnelle `classe` : si présente, l'élève est automatiquement assigné
à la classe correspondante (créée si elle n'existe pas encore).
"""

import csv
import io
import re
from typing import Optional, Tuple

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.models.school_class import ClassStudent, SchoolClass
from app.models.student import Student
from app.schemas.student import ImportError, StudentImportReport, StudentImportRow

# Colonnes acceptées dans le CSV (noms en français, insensibles à la casse)
REQUIRED_COLUMNS = {"nom", "prenom"}
OPTIONAL_COLUMNS = {"email", "classe"}
EMAIL_REGEX = re.compile(r"^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$")


def _normalize_header(raw: str) -> str:
    """Normalise un nom de colonne : minuscules, sans espaces."""
    return raw.strip().lower()


def _detect_separator(sample: str) -> str:
    """Détecte le séparateur CSV (virgule ou point-virgule)."""
    if sample.count(";") >= sample.count(","):
        return ";"
    return ","


def _get_or_create_class(db: Session, class_name: str) -> SchoolClass:
    """
    Retourne la classe portant ce nom (insensible à la casse),
    ou la crée si elle n'existe pas encore.
    """
    existing = db.execute(
        select(SchoolClass).where(func.lower(SchoolClass.name) == class_name.lower())
    ).scalar_one_or_none()

    if existing:
        return existing

    new_class = SchoolClass(name=class_name.strip())
    db.add(new_class)
    db.flush()  # obtenir l'ID sans committer
    return new_class


def parse_and_import_csv(
    content: bytes, db: Session
) -> StudentImportReport:
    """
    Parse le CSV, valide chaque ligne, détecte les doublons et insère en bulk.

    Règles :
    - Colonnes requises : nom, prenom
    - Colonnes optionnelles : email, classe
    - Si `classe` est présente : l'élève est assigné à cette classe (créée si nécessaire)
    - Doublon intra-fichier : même nom+prenom (insensible à la casse)
    - Doublon BDD : idem contre les élèves existants
    """
    text = content.decode("utf-8-sig")  # utf-8-sig gère le BOM Excel
    separator = _detect_separator(text.splitlines()[0] if text.splitlines() else "")

    reader = csv.DictReader(io.StringIO(text), delimiter=separator)

    # Vérification des colonnes obligatoires
    if reader.fieldnames is None:
        return StudentImportReport(
            total_rows=0, inserted=0, rejected=0,
            duplicates_in_file=0, duplicates_in_db=0,
            errors=[ImportError(row=0, content="", reason="Fichier CSV vide ou illisible")]
        )

    normalized_fields = {_normalize_header(f) for f in reader.fieldnames}
    missing = REQUIRED_COLUMNS - normalized_fields
    if missing:
        return StudentImportReport(
            total_rows=0, inserted=0, rejected=0,
            duplicates_in_file=0, duplicates_in_db=0,
            errors=[ImportError(
                row=0, content=str(reader.fieldnames),
                reason=f"Colonnes manquantes : {', '.join(missing)}"
            )]
        )

    has_classe_column = "classe" in normalized_fields

    # Construire un mapping nom_normalise → nom_original
    field_map = {_normalize_header(f): f for f in reader.fieldnames}

    valid_rows: list[StudentImportRow] = []
    errors: list[ImportError] = []
    seen_in_file: set[Tuple[str, str]] = set()  # (last_name_lower, first_name_lower)
    duplicates_in_file = 0
    row_num = 1

    for row_num, row in enumerate(reader, start=2):  # ligne 1 = header
        raw_last = row.get(field_map["nom"], "").strip()
        raw_first = row.get(field_map["prenom"], "").strip()
        raw_email = row.get(field_map.get("email", ""), "").strip() if "email" in field_map else ""
        raw_classe = row.get(field_map.get("classe", ""), "").strip() if has_classe_column else ""

        # Ligne vide
        if not raw_last and not raw_first:
            continue

        # Validation nom/prénom non vides
        if not raw_last or not raw_first:
            errors.append(ImportError(
                row=row_num,
                content=f"{raw_last}, {raw_first}",
                reason="Nom ou prénom manquant"
            ))
            continue

        # Validation email si fourni
        if raw_email and not EMAIL_REGEX.match(raw_email):
            errors.append(ImportError(
                row=row_num,
                content=f"{raw_last}, {raw_first}, {raw_email}",
                reason=f"Format email invalide : {raw_email}"
            ))
            continue

        # Doublon intra-fichier
        key = (raw_last.lower(), raw_first.lower())
        if key in seen_in_file:
            duplicates_in_file += 1
            errors.append(ImportError(
                row=row_num,
                content=f"{raw_last}, {raw_first}",
                reason="Doublon dans le fichier CSV"
            ))
            continue
        seen_in_file.add(key)

        valid_rows.append(StudentImportRow(
            last_name=raw_last,
            first_name=raw_first,
            email=raw_email or None,
            classe=raw_classe or None,
        ))

    total_rows = row_num - 1 if valid_rows or errors else 0

    if not valid_rows:
        return StudentImportReport(
            total_rows=total_rows,
            inserted=0,
            rejected=len(errors),
            duplicates_in_file=duplicates_in_file,
            duplicates_in_db=0,
            errors=errors
        )

    # Détection doublons contre la BDD (batch query)
    keys_to_check = [(r.last_name.lower(), r.first_name.lower()) for r in valid_rows]
    existing = db.execute(
        select(
            func.lower(Student.last_name),
            func.lower(Student.first_name)
        ).where(
            func.lower(Student.last_name).in_([k[0] for k in keys_to_check])
        )
    ).fetchall()
    existing_set = {(row[0], row[1]) for row in existing}

    to_insert: list[StudentImportRow] = []
    duplicates_in_db = 0

    for student in valid_rows:
        key = (student.last_name.lower(), student.first_name.lower())
        if key in existing_set:
            duplicates_in_db += 1
            errors.append(ImportError(
                row=0,
                content=f"{student.last_name}, {student.first_name}",
                reason="Élève déjà présent en base de données"
            ))
        else:
            to_insert.append(student)

    # Insertion bulk des élèves
    if to_insert:
        db.bulk_insert_mappings(Student, [
            {
                "first_name": s.first_name,
                "last_name": s.last_name,
                "email": s.email,
            }
            for s in to_insert
        ])
        db.flush()  # obtenir les IDs avant d'assigner les classes

        # Assignation aux classes si la colonne `classe` est présente
        if has_classe_column:
            _assign_classes(db, to_insert)

        db.commit()

    return StudentImportReport(
        total_rows=total_rows,
        inserted=len(to_insert),
        rejected=len(errors),
        duplicates_in_file=duplicates_in_file,
        duplicates_in_db=duplicates_in_db,
        errors=errors
    )


def _assign_classes(db: Session, students: list[StudentImportRow]) -> None:
    """
    Assigne chaque élève à sa classe après insertion.
    Crée la classe si elle n'existe pas encore.
    Ignore les élèves sans classe renseignée.
    """
    # Regrouper les élèves par classe pour minimiser les requêtes
    classes_map: dict[str, Optional[SchoolClass]] = {}

    for student in students:
        if not student.classe:
            continue

        class_name = student.classe.strip()
        if class_name not in classes_map:
            classes_map[class_name] = _get_or_create_class(db, class_name)

    if not classes_map:
        return

    # Récupérer les IDs des élèves qu'on vient d'insérer
    inserted_students = db.execute(
        select(Student.id, func.lower(Student.last_name), func.lower(Student.first_name))
        .where(
            func.lower(Student.last_name).in_(
                [s.last_name.lower() for s in students if s.classe]
            )
        )
    ).fetchall()

    # Construire un index (last_name_lower, first_name_lower) → student_id
    student_id_map = {
        (row[1], row[2]): row[0]
        for row in inserted_students
    }

    # Récupérer les assignations existantes pour éviter les doublons
    all_class_ids = [c.id for c in classes_map.values() if c]
    existing_assignments = set()
    if all_class_ids:
        existing_rows = db.execute(
            select(ClassStudent.class_id, ClassStudent.student_id)
            .where(ClassStudent.class_id.in_(all_class_ids))
        ).fetchall()
        existing_assignments = {(row[0], row[1]) for row in existing_rows}

    # Insérer les assignations manquantes
    assignments_to_insert = []
    for student in students:
        if not student.classe:
            continue

        school_class = classes_map.get(student.classe.strip())
        if not school_class:
            continue

        student_id = student_id_map.get(
            (student.last_name.lower(), student.first_name.lower())
        )
        if not student_id:
            continue

        if (school_class.id, student_id) not in existing_assignments:
            assignments_to_insert.append({
                "class_id": school_class.id,
                "student_id": student_id,
            })

    if assignments_to_insert:
        db.bulk_insert_mappings(ClassStudent, assignments_to_insert)
