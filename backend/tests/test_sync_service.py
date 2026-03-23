"""
Tests unitaires pour le service de synchronisation (US 3.1 + US 3.2).

US 3.1 — idempotence, doublons intra/inter-batch, batch vide, scan_sequence, is_manual.
US 3.2 — fusion multi-enseignants, MERGED_OLDEST, SUPERSEDED, anomalies temporelles.

Note : _detect_temporal_anomalies est patchée dans tous les tests de sync_attendances
pour isoler la logique de fusion des requêtes de détection d'anomalies.

Note 2 : Depuis l'ajout de la validation checkpoint (étape 2b), chaque scan non-doublon
requiert un db.execute supplémentaire pour vérifier l'existence du checkpoint.
Ordre des execute par scan : history check → checkpoint check → canonical check.
"""

import uuid
from datetime import datetime, timezone
from unittest.mock import MagicMock, call, patch

from app.models.attendance import Attendance, AttendanceHistory
from app.schemas.sync import ScanItem
from app.services.sync_service import _is_strictly_older, sync_attendances


# ----------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------

_DUMMY_CP_ID = uuid.uuid4()  # ID checkpoint "existant" utilisé dans les mocks


def make_scan(
    client_uuid=None,
    student_id=None,
    checkpoint_id=None,
    trip_id=None,
    scanned_at=None,
    scan_method="NFC_PHYSICAL",
    scan_sequence=1,
    is_manual=False,
    justification=None,
    comment=None,
) -> ScanItem:
    return ScanItem(
        client_uuid=client_uuid or uuid.uuid4(),
        student_id=student_id or uuid.uuid4(),
        checkpoint_id=checkpoint_id or _DUMMY_CP_ID,
        trip_id=trip_id or uuid.uuid4(),
        scanned_at=scanned_at or datetime(2026, 2, 20, 14, 32, 15, tzinfo=timezone.utc),
        scan_method=scan_method,
        scan_sequence=scan_sequence,
        is_manual=is_manual,
        justification=justification,
        comment=comment,
    )


def make_execute_result(scalar_value):
    """Mock d'un résultat db.execute() avec scalar() prédéfini."""
    r = MagicMock()
    r.scalar.return_value = scalar_value
    return r


def make_db(*scalar_values):
    """
    Mock de session DB avec une séquence de résultats pour db.execute().
    Chaque valeur dans scalar_values correspond à un appel successif à execute().scalar().
    Les appels supplémentaires (ex: détection anomalies, SyncLog) retournent None par défaut.
    """
    db = MagicMock()
    results = [make_execute_result(v) for v in scalar_values]
    # Appels excédentaires (détection d'anomalies, SyncLog, etc.) → résultat vide
    extra = make_execute_result(None)
    db.execute.side_effect = results + [extra] * 20
    return db


_PATCH = "app.services.sync_service._detect_temporal_anomalies"


# ================================================================
# Batch vide
# ================================================================

@patch(_PATCH, return_value=[])
def test_batch_vide(_):
    """Batch vide → 0 inséré, réponse cohérente."""
    db = MagicMock()
    db.execute.side_effect = [make_execute_result(None)] * 20
    result = sync_attendances(db, scans=[], device_id="device-01")

    assert result.total_received == 0
    assert result.total_inserted == 0
    assert result.total_merged == 0
    assert result.accepted == []
    assert result.duplicate == []
    assert result.merged == []
    db.commit.assert_called_once()


# ================================================================
# Scan unique nouveau
# ================================================================

@patch(_PATCH, return_value=[])
def test_scan_unique_nouveau(_):
    """Un scan inconnu → 1 entry history + 1 canonical insérés."""
    # Trois execute : history check (None) + checkpoint check (exists) + canonical check (None)
    db = make_db(None, _DUMMY_CP_ID, None)
    scan = make_scan()

    result = sync_attendances(db, scans=[scan])

    assert result.total_received == 1
    assert result.total_inserted == 1
    assert result.total_merged == 0
    assert str(scan.client_uuid) in result.accepted
    assert result.duplicate == []
    assert result.merged == []
    db.commit.assert_called_once()


# ================================================================
# Idempotence : client_uuid déjà dans l'historique
# ================================================================

@patch(_PATCH, return_value=[])
def test_doublon_inter_batch(_):
    """client_uuid déjà en history → doublon, aucun add d'history/canonical."""
    existing_history = MagicMock(spec=AttendanceHistory)
    db = make_db(existing_history)  # history check → trouvé
    scan = make_scan()

    result = sync_attendances(db, scans=[scan])

    assert result.total_received == 1
    assert result.total_inserted == 0
    assert str(scan.client_uuid) in result.duplicate
    db.commit.assert_called_once()


# ================================================================
# Doublons intra-batch (même UUID deux fois dans le même batch)
# ================================================================

@patch(_PATCH, return_value=[])
def test_doublon_intra_batch(_):
    """Même UUID deux fois dans le batch → 1 traité, 1 doublon intra."""
    # Premier scan : history=None, checkpoint=exists, canonical=None
    db = make_db(None, _DUMMY_CP_ID, None)
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


# ================================================================
# Mix : nouveaux + doublons
# ================================================================

@patch(_PATCH, return_value=[])
def test_mix_nouveaux_et_doublons(_):
    """2 nouveaux scans + 1 doublon history → 2 insérés, 1 doublon."""
    uid_existing = uuid.uuid4()
    scan_new1 = make_scan()
    scan_new2 = make_scan()
    scan_dup = make_scan(client_uuid=uid_existing)

    # Ordre : new1(history,cp,canonical), new2(history,cp,canonical), dup(history=exists)
    # new2 checkpoint peut être en cache si même cp_id → mais nos scans utilisent le même _DUMMY_CP_ID
    db = make_db(
        None, _DUMMY_CP_ID, None,  # new1: history, checkpoint, canonical
        None,                       # new2: history (checkpoint en cache)
        None,                       # new2: canonical
        MagicMock(spec=AttendanceHistory),  # dup: history → trouvé
    )

    result = sync_attendances(db, scans=[scan_new1, scan_new2, scan_dup])

    assert result.total_received == 3
    assert result.total_inserted == 2
    assert len(result.accepted) == 2
    assert len(result.duplicate) == 1
    assert str(uid_existing) in result.duplicate


# ================================================================
# Méthodes de scan valides
# ================================================================

@patch(_PATCH, return_value=[])
def test_scan_methodes_valides(_):
    """Toutes les méthodes de scan valides sont acceptées."""
    for method in ("NFC_PHYSICAL", "QR_PHYSICAL", "QR_DIGITAL", "MANUAL"):
        db = make_db(None, _DUMMY_CP_ID, None)
        scan = make_scan(scan_method=method)
        result = sync_attendances(db, scans=[scan])
        assert result.total_inserted == 1, f"Méthode {method} devrait être acceptée"


# ================================================================
# Champs de l'objet Attendance créé
# ================================================================

@patch(_PATCH, return_value=[])
def test_champs_attendance_corrects(_):
    """Les champs sont correctement mappés sur Attendance (second add = canonique)."""
    db = make_db(None, _DUMMY_CP_ID, None)
    scan = make_scan(scan_method="QR_DIGITAL")

    sync_attendances(db, scans=[scan])

    # Parmi les objets ajoutés, trouver history et canonical
    added = [c[0][0] for c in db.add.call_args_list]
    histories = [o for o in added if isinstance(o, AttendanceHistory)]
    canonicals = [o for o in added if isinstance(o, Attendance)]

    assert len(histories) == 1
    assert len(canonicals) == 1

    canonical_obj = canonicals[0]
    assert canonical_obj.client_uuid == scan.client_uuid
    assert canonical_obj.student_id == scan.student_id
    assert canonical_obj.checkpoint_id == scan.checkpoint_id
    assert canonical_obj.trip_id == scan.trip_id
    assert canonical_obj.scanned_at == scan.scanned_at
    assert canonical_obj.scan_method == "QR_DIGITAL"
    assert canonical_obj.scan_sequence == 1
    assert canonical_obj.is_manual is False
    assert canonical_obj.justification is None
    assert canonical_obj.comment is None


# ================================================================
# scan_sequence (US 2.6)
# ================================================================

@patch(_PATCH, return_value=[])
def test_scan_sequence_transmis(_):
    """scan_sequence est bien persisté sur Attendance."""
    db = make_db(None, _DUMMY_CP_ID, None)
    scan = make_scan(scan_sequence=2)

    sync_attendances(db, scans=[scan])

    added = [c[0][0] for c in db.add.call_args_list]
    canonicals = [o for o in added if isinstance(o, Attendance)]
    assert canonicals[0].scan_sequence == 2


# ================================================================
# Marquage manuel (US 2.4)
# ================================================================

@patch(_PATCH, return_value=[])
def test_is_manual_et_justification_transmis(_):
    """is_manual=True et justification sont bien persistés."""
    db = make_db(None, _DUMMY_CP_ID, None)
    scan = make_scan(
        scan_method="MANUAL",
        is_manual=True,
        justification="BADGE_MISSING",
        comment="Bracelet oublié à la maison",
    )

    sync_attendances(db, scans=[scan])

    added = [c[0][0] for c in db.add.call_args_list]
    canonicals = [o for o in added if isinstance(o, Attendance)]
    assert canonicals[0].is_manual is True
    assert canonicals[0].justification == "BADGE_MISSING"
    assert canonicals[0].comment == "Bracelet oublié à la maison"


# ================================================================
# Helper _is_strictly_older
# ================================================================

def test_is_strictly_older_naive():
    """Timestamps naïfs : comparaison directe."""
    older = datetime(2026, 3, 21, 10, 0, 0)
    newer = datetime(2026, 3, 21, 14, 0, 0)
    assert _is_strictly_older(older, newer) is True
    assert _is_strictly_older(newer, older) is False
    assert _is_strictly_older(older, older) is False


def test_is_strictly_older_aware_vs_naive():
    """Un aware et un naive → normalisation sans TypeError."""
    aware = datetime(2026, 3, 21, 10, 0, 0, tzinfo=timezone.utc)
    naive = datetime(2026, 3, 21, 14, 0, 0)
    # Ne doit pas lever d'exception
    result = _is_strictly_older(aware, naive)
    assert result is True
