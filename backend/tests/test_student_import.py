"""
Tests unitaires pour le service d'import CSV élèves (US 1.1).
"""

import pytest
from unittest.mock import MagicMock, patch

from app.services.student_import import parse_and_import_csv


def make_db_mock(existing_students=None):
    """Crée un mock de session SQLAlchemy sans BDD réelle."""
    db = MagicMock()
    existing = existing_students or []
    db.execute.return_value.fetchall.return_value = existing
    # scalar_one_or_none utilisé par _get_or_create_class → retourne None (classe à créer)
    db.execute.return_value.scalar_one_or_none.return_value = None
    return db


# --- Cas nominaux ---

def test_import_csv_basique():
    """Import simple avec nom, prenom, email."""
    csv_content = b"nom,prenom,email\nDupont,Jean,jean@test.be\nMartin,Marie,\n"
    db = make_db_mock()

    report = parse_and_import_csv(csv_content, db)

    assert report.inserted == 2
    assert report.rejected == 0
    assert report.duplicates_in_file == 0
    assert report.duplicates_in_db == 0


def test_import_csv_sans_email():
    """Import avec colonnes nom et prenom uniquement."""
    csv_content = b"nom,prenom\nDupont,Jean\nMartin,Marie\n"
    db = make_db_mock()

    report = parse_and_import_csv(csv_content, db)

    assert report.inserted == 2
    assert report.rejected == 0


def test_import_csv_separateur_point_virgule():
    """Le séparateur point-virgule (export Excel FR) doit être détecté."""
    csv_content = b"nom;prenom;email\nDupont;Jean;jean@test.be\n"
    db = make_db_mock()

    report = parse_and_import_csv(csv_content, db)

    assert report.inserted == 1
    assert report.rejected == 0


def test_import_csv_avec_bom():
    """Les fichiers CSV avec BOM UTF-8 (Excel) doivent être gérés."""
    csv_content = "nom,prenom\nDupont,Jean\n".encode("utf-8-sig")
    db = make_db_mock()

    report = parse_and_import_csv(csv_content, db)

    assert report.inserted == 1


# --- Détection de doublons ---

def test_doublon_intra_fichier():
    """Deux lignes avec le même nom+prénom dans le CSV → une seule insérée."""
    csv_content = b"nom,prenom\nDupont,Jean\nDupont,Jean\n"
    db = make_db_mock()

    report = parse_and_import_csv(csv_content, db)

    assert report.inserted == 1
    assert report.duplicates_in_file == 1


def test_doublon_intra_fichier_insensible_casse():
    """La détection de doublons est insensible à la casse."""
    csv_content = b"nom,prenom\nDupont,Jean\ndupont,jean\n"
    db = make_db_mock()

    report = parse_and_import_csv(csv_content, db)

    assert report.inserted == 1
    assert report.duplicates_in_file == 1


def test_doublon_en_base():
    """Un élève déjà en BDD ne doit pas être inséré à nouveau."""
    csv_content = b"nom,prenom\nDupont,Jean\n"
    db = make_db_mock(existing_students=[("dupont", "jean")])

    report = parse_and_import_csv(csv_content, db)

    assert report.inserted == 0
    assert report.duplicates_in_db == 1


# --- Validation des données ---

def test_email_invalide_rejete():
    """Une ligne avec un email malformé doit être rejetée."""
    csv_content = b"nom,prenom,email\nDupont,Jean,pas-un-email\n"
    db = make_db_mock()

    report = parse_and_import_csv(csv_content, db)

    assert report.inserted == 0
    assert report.rejected == 1
    assert "email" in report.errors[0].reason.lower()


def test_ligne_nom_manquant_rejetee():
    """Une ligne sans nom doit être rejetée."""
    csv_content = b"nom,prenom\n,Jean\n"
    db = make_db_mock()

    report = parse_and_import_csv(csv_content, db)

    assert report.inserted == 0
    assert report.rejected == 1


def test_colonne_manquante():
    """Un CSV sans colonne 'nom' ou 'prenom' doit retourner une erreur globale."""
    csv_content = b"first_name,last_name\nJean,Dupont\n"
    db = make_db_mock()

    report = parse_and_import_csv(csv_content, db)

    assert report.inserted == 0
    assert len(report.errors) > 0
    assert "manquantes" in report.errors[0].reason.lower()


def test_fichier_vide():
    """Un fichier CSV vide doit retourner un rapport sans insertion."""
    csv_content = b""
    db = make_db_mock()

    report = parse_and_import_csv(csv_content, db)

    assert report.inserted == 0


def test_lignes_vides_ignorees():
    """Les lignes vides dans le CSV sont ignorées silencieusement."""
    csv_content = b"nom,prenom\nDupont,Jean\n\n\nMartin,Marie\n"
    db = make_db_mock()

    report = parse_and_import_csv(csv_content, db)

    assert report.inserted == 2
    assert report.rejected == 0


# --- Colonne classe (optionnelle) ---

def test_import_csv_avec_colonne_classe():
    """CSV avec colonne classe : les élèves sont importés sans erreur."""
    csv_content = b"nom,prenom,email,classe\nDupont,Jean,jean@test.be,3A\nMartin,Marie,,3B\n"
    db = make_db_mock()

    report = parse_and_import_csv(csv_content, db)

    assert report.inserted == 2
    assert report.rejected == 0


def test_import_csv_classe_vide_acceptee():
    """Un élève sans classe dans la colonne classe est quand même importé."""
    csv_content = b"nom,prenom,classe\nDupont,Jean,3A\nMartin,Marie,\n"
    db = make_db_mock()

    report = parse_and_import_csv(csv_content, db)

    assert report.inserted == 2
    assert report.rejected == 0


def test_import_csv_sans_colonne_classe():
    """Un CSV sans colonne classe continue de fonctionner normalement."""
    csv_content = b"nom,prenom,email\nDupont,Jean,jean@test.be\n"
    db = make_db_mock()

    report = parse_and_import_csv(csv_content, db)

    assert report.inserted == 1
    assert report.rejected == 0


def test_import_csv_classe_creee_si_inexistante():
    """Si la classe n'existe pas en BDD, _get_or_create_class doit être appelé."""
    csv_content = b"nom,prenom,classe\nDupont,Jean,3A\n"
    db = make_db_mock()

    parse_and_import_csv(csv_content, db)

    # bulk_insert_mappings doit avoir été appelé (élève + assignation classe)
    assert db.bulk_insert_mappings.called


def test_import_csv_classe_plusieurs_eleves_meme_classe():
    """Plusieurs élèves dans la même classe → une seule classe créée."""
    csv_content = b"nom,prenom,classe\nDupont,Jean,3A\nMartin,Marie,3A\nLambert,Thomas,3B\n"
    db = make_db_mock()

    report = parse_and_import_csv(csv_content, db)

    assert report.inserted == 3
    assert report.rejected == 0
