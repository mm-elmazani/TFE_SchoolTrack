"""
Tests unitaires pour le service de synchronisation offline → online (US 3.1).
Couverture : idempotence, doublons intra-batch, batch vide, multi-scans,
scan_sequence (US 2.6), is_manual + justification (US 2.4).
"""

import uuid
from datetime import datetime, timezone
from unittest.mock import MagicMock

from app.models.attendance import Attendance
from app.schemas.sync import ScanItem
from app.services.sync_service import sync_attendances


# --- Helper ---

def make_scan(
    client_uuid=None,
    student_id=None,
    checkpoint_id=None,
    trip_id=None,
    scan_method="NFC_PHYSICAL",
    scan_sequence=1,
    is_manual=False,
    justification=None,
    comment=None,
) -> ScanItem:
    return ScanItem(
        client_uuid=client_uuid or uuid.uuid4(),
        student_id=student_id or uuid.uuid4(),
        checkpoint_id=checkpoint_id or uuid.uuid4(),
        trip_id=trip_id or uuid.uuid4(),
        scanned_at=datetime(2026, 2, 20, 14, 32, 15, tzinfo=timezone.utc),
        scan_method=scan_method,
        scan_sequence=scan_sequence,
        is_manual=is_manual,
        justification=justification,
        comment=comment,
    )


def make_db(existing_attendance=None):
    """Mock de session DB. existing_attendance = valeur retournée par .scalar() (idempotence check)."""
    db = MagicMock()
    result_mock = MagicMock()
    result_mock.scalar.return_value = existing_attendance
    db.execute.return_value = result_mock
    return db


# ============================================================
# Batch vide
# ============================================================

def test_batch_vide():
    """Batch vide → 0 inséré, réponse cohérente."""
    db = make_db()
    result = sync_attendances(db, scans=[], device_id="device-01")

    assert result.total_received == 0
    assert result.total_inserted == 0
    assert result.accepted == []
    assert result.duplicate == []
    db.add.assert_not_called()
    db.commit.assert_called_once()


# ============================================================
# Scan unique nouveau
# ============================================================

def test_scan_unique_nouveau():
    """Un scan avec UUID inconnu → 1 inséré."""
    db = make_db(existing_attendance=None)
    scan = make_scan()

    result = sync_attendances(db, scans=[scan])

    assert result.total_received == 1
    assert result.total_inserted == 1
    assert str(scan.client_uuid) in result.accepted
    assert result.duplicate == []
    db.add.assert_called_once()
    db.commit.assert_called_once()


# ============================================================
# Idempotence : UUID déjà en base
# ============================================================

def test_doublon_inter_batch():
    """UUID déjà présent en base → ignoré, pas d'insert."""
    existing = MagicMock(spec=Attendance)
    db = make_db(existing_attendance=existing)
    scan = make_scan()

    result = sync_attendances(db, scans=[scan])

    assert result.total_received == 1
    assert result.total_inserted == 0
    assert result.accepted == []
    assert str(scan.client_uuid) in result.duplicate
    db.add.assert_not_called()
    db.commit.assert_called_once()


# ============================================================
# Doublons intra-batch (même UUID deux fois dans le même batch)
# ============================================================

def test_doublon_intra_batch():
    """Même UUID deux fois dans le même batch → 1 inséré, 1 doublon."""
    db = make_db(existing_attendance=None)  # Pas en base
    uid = uuid.uuid4()
    scan1 = make_scan(client_uuid=uid)
    scan2 = make_scan(client_uuid=uid)  # Même UUID

    result = sync_attendances(db, scans=[scan1, scan2])

    assert result.total_received == 2
    assert result.total_inserted == 1
    assert len(result.accepted) == 1
    assert len(result.duplicate) == 1
    assert str(uid) in result.accepted
    assert str(uid) in result.duplicate
    db.add.assert_called_once()


# ============================================================
# Mix : nouveaux + doublons
# ============================================================

def test_mix_nouveaux_et_doublons():
    """Batch avec 2 nouveaux et 1 doublon DB → 2 insérés, 1 doublon."""
    uid_existing = uuid.uuid4()
    scan_new1 = make_scan()
    scan_new2 = make_scan()
    scan_duplicate = make_scan(client_uuid=uid_existing)

    db = MagicMock()

    # scan_new1 → pas en base
    result_new1 = MagicMock()
    result_new1.scalar.return_value = None
    # scan_new2 → pas en base
    result_new2 = MagicMock()
    result_new2.scalar.return_value = None
    # scan_duplicate → déjà en base
    result_dup = MagicMock()
    result_dup.scalar.return_value = MagicMock(spec=Attendance)

    db.execute.side_effect = [result_new1, result_new2, result_dup]

    result = sync_attendances(db, scans=[scan_new1, scan_new2, scan_duplicate])

    assert result.total_received == 3
    assert result.total_inserted == 2
    assert len(result.accepted) == 2
    assert len(result.duplicate) == 1
    assert str(uid_existing) in result.duplicate
    assert db.add.call_count == 2


# ============================================================
# Méthodes de scan valides
# ============================================================

def test_scan_methodes_valides():
    """Toutes les méthodes de scan valides sont acceptées."""
    for method in ("NFC_PHYSICAL", "QR_PHYSICAL", "QR_DIGITAL", "MANUAL"):
        db = make_db(existing_attendance=None)
        scan = make_scan(scan_method=method)
        result = sync_attendances(db, scans=[scan])
        assert result.total_inserted == 1, f"Méthode {method} devrait être acceptée"


# ============================================================
# Champs de l'enregistrement Attendance créé
# ============================================================

def test_champs_attendance_corrects():
    """Vérifie que les champs de base sont correctement mappés sur Attendance."""
    db = make_db(existing_attendance=None)
    scan = make_scan(scan_method="QR_DIGITAL")

    sync_attendances(db, scans=[scan])

    db.add.assert_called_once()
    added_obj = db.add.call_args[0][0]

    assert isinstance(added_obj, Attendance)
    assert added_obj.client_uuid == scan.client_uuid
    assert added_obj.student_id == scan.student_id
    assert added_obj.checkpoint_id == scan.checkpoint_id
    assert added_obj.trip_id == scan.trip_id
    assert added_obj.scanned_at == scan.scanned_at
    assert added_obj.scan_method == "QR_DIGITAL"
    assert added_obj.scan_sequence == 1
    assert added_obj.is_manual is False
    assert added_obj.justification is None
    assert added_obj.comment is None


# ============================================================
# scan_sequence (US 2.6 — scans multiples par checkpoint)
# ============================================================

def test_scan_sequence_doublon_transmis():
    """scan_sequence=2 (doublon) est bien persisté sur Attendance."""
    db = make_db(existing_attendance=None)
    scan = make_scan(scan_sequence=2)

    sync_attendances(db, scans=[scan])

    added_obj = db.add.call_args[0][0]
    assert added_obj.scan_sequence == 2


def test_scan_sequence_premier_scan():
    """scan_sequence=1 (premier scan) est persisté par défaut."""
    db = make_db(existing_attendance=None)
    scan = make_scan(scan_sequence=1)

    sync_attendances(db, scans=[scan])

    added_obj = db.add.call_args[0][0]
    assert added_obj.scan_sequence == 1


# ============================================================
# Marquage manuel (US 2.4) — is_manual + justification + comment
# ============================================================

def test_is_manual_et_justification_transmis():
    """is_manual=True et justification sont bien persistés sur Attendance."""
    db = make_db(existing_attendance=None)
    scan = make_scan(
        scan_method="MANUAL",
        is_manual=True,
        justification="BADGE_MISSING",
        comment="Bracelet oublié à la maison",
    )

    sync_attendances(db, scans=[scan])

    added_obj = db.add.call_args[0][0]
    assert added_obj.is_manual is True
    assert added_obj.justification == "BADGE_MISSING"
    assert added_obj.comment == "Bracelet oublié à la maison"


def test_is_manual_sans_comment():
    """Marquage manuel sans commentaire : comment=None accepté."""
    db = make_db(existing_attendance=None)
    scan = make_scan(
        scan_method="MANUAL",
        is_manual=True,
        justification="SCANNER_FAILURE",
    )

    sync_attendances(db, scans=[scan])

    added_obj = db.add.call_args[0][0]
    assert added_obj.is_manual is True
    assert added_obj.justification == "SCANNER_FAILURE"
    assert added_obj.comment is None
