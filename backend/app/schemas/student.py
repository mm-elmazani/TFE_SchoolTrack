"""
Schémas Pydantic pour les élèves.
"""

from typing import List, Optional
from pydantic import BaseModel, EmailStr, field_validator


class StudentImportRow(BaseModel):
    """Représente une ligne valide du CSV après parsing."""
    first_name: str
    last_name: str
    email: Optional[str] = None
    classe: Optional[str] = None  # nom de la classe (optionnel, colonne CSV)


class ImportError(BaseModel):
    """Détail d'une ligne rejetée lors de l'import."""
    row: int
    content: str
    reason: str


class StudentImportReport(BaseModel):
    """Rapport retourné après un import CSV."""
    total_rows: int
    inserted: int
    rejected: int
    duplicates_in_file: int
    duplicates_in_db: int
    errors: List[ImportError]
