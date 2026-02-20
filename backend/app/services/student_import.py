"""
Service d'import CSV pour les élèves.
Gère le parsing, la validation, la détection de doublons et l'insertion bulk.
"""

import csv
import io
import re
from typing import Tuple

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.models.student import Student
from app.schemas.student import ImportError, StudentImportReport, StudentImportRow

# Colonnes acceptées dans le CSV (noms en français, insensibles à la casse)
REQUIRED_COLUMNS = {"nom", "prenom"}
OPTIONAL_COLUMNS = {"email"}
EMAIL_REGEX = re.compile(r"^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$")


def _normalize_header(raw: str) -> str:
    """Normalise un nom de colonne : minuscules, sans espaces."""
    return raw.strip().lower()


def _detect_separator(sample: str) -> str:
    """Détecte le séparateur CSV (virgule ou point-virgule)."""
    if sample.count(";") >= sample.count(","):
        return ";"
    return ","


def parse_and_import_csv(
    content: bytes, db: Session
) -> StudentImportReport:
    """
    Parse le CSV, valide chaque ligne, détecte les doublons et insère en bulk.

    Règles :
    - Colonnes requises : nom, prenom
    - Colonne optionnelle : email
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

    # Construire un mapping nom_normalise → nom_original
    field_map = {_normalize_header(f): f for f in reader.fieldnames}

    valid_rows: list[StudentImportRow] = []
    errors: list[ImportError] = []
    seen_in_file: set[Tuple[str, str]] = set()  # (last_name_lower, first_name_lower)
    duplicates_in_file = 0

    for row_num, row in enumerate(reader, start=2):  # ligne 1 = header
        raw_last = row.get(field_map["nom"], "").strip()
        raw_first = row.get(field_map["prenom"], "").strip()
        raw_email = row.get(field_map.get("email", ""), "").strip() if "email" in field_map else ""

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

    to_insert: list[dict] = []
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
            to_insert.append({
                "first_name": student.first_name,
                "last_name": student.last_name,
                "email": student.email,
            })

    # Insertion bulk
    if to_insert:
        db.bulk_insert_mappings(Student, to_insert)
        db.commit()

    return StudentImportReport(
        total_rows=total_rows,
        inserted=len(to_insert),
        rejected=len(errors),
        duplicates_in_file=duplicates_in_file,
        duplicates_in_db=duplicates_in_db,
        errors=errors
    )
