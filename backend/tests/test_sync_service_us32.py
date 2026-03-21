"""
Tests unitaires pour la logique de fusion multi-enseignants (US 3.2).

Scénarios couverts :
- Fusion : 2e enseignant avec scan plus ancien → remplace le canonique (MERGED_OLDEST)
- Supersession : 2e enseignant avec scan plus récent → canonique conservé (SUPERSEDED)
- Même timestamp → canonique conservé (pas de remplacement à égalité)
- Rapport de fusion : merged + total_merged cohérents
- Détection anomalies temporelles : timestamps non croissants entre checkpoints
- Plusieurs conflits dans le même batch
- Batch multi-étudiants avec conflits mixtes
"""

import uuid
from datetime import datetime, timezone
from unittest.mock import MagicMock, patch

from app.models.attendance import Attendance, AttendanceHistory
from app.models.checkpoint import Checkpoint
from app.schemas.sync import ScanItem
from app.services.sync_service import _detect_temporal_anomalies, sync_attendances

_PATCH = "app.services.sync_service._detect_temporal_anomalies"


# ----------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------

def make_scan(
    student_id=None,
    checkpoint_id=None,
    trip_id=None,
    scanned_at=None,
    client_uuid=None,
    scan_method="NFC_PHYSICAL",
) -> ScanItem:
    return ScanItem(
        client_uuid=client_uuid or uuid.uuid4(),
        student_id=student_id or uuid.uuid4(),
        checkpoint_id=checkpoint_id or uuid.uuid4(),
        trip_id=trip_id or uuid.uuid4(),
        scanned_at=scanned_at or datetime(2026, 3, 21, 12, 0, 0),
        scan_method=scan_method,
    )


def make_execute_result(scalar_value):
    r = MagicMock()
    r.scalar.return_value = scalar_value
    return r


def make_db(*scalar_values):
    db = MagicMock()
    results = [make_execute_result(v) for v in scalar_values]
    extra = make_execute_result(None)
    db.execute.side_effect = results + [extra] * 20
    return db


def make_canonical(scanned_at: datetime) -> Attendance:
    """Crée un mock d'Attendance canonique existant."""
    canonical = MagicMock(spec=Attendance)
    canonical.scanned_at = scanned_at
    return canonical


# ================================================================
# Fusion : scan plus ancien remplace le canonique
# ================================================================

@patch(_PATCH, return_value=[])
def test_scan_plus_ancien_remplace_canonique(_):
    """
    2e enseignant synchronise un scan plus ancien → MERGED_OLDEST.
    Le canonique est mis à jour avec le nouveau (plus ancien) scanned_at.
    """
    student_id = uuid.uuid4()
    checkpoint_id = uuid.uuid4()
    trip_id = uuid.uuid4()

    canonical = make_canonical(scanned_at=datetime(2026, 3, 21, 14, 0, 0))

    # Nouveau scan à 13:30 (plus ancien que le canonique à 14:00)
    scan = make_scan(
        student_id=student_id,
        checkpoint_id=checkpoint_id,
        trip_id=trip_id,
        scanned_at=datetime(2026, 3, 21, 13, 30, 0),
    )

    db = make_db(None, canonical)  # history=None, canonical=existant

    result = sync_attendances(db, scans=[scan])

    # Résultat : fusionné (pas inséré)
    assert result.total_inserted == 0
    assert result.total_merged == 1
    assert str(scan.client_uuid) in result.merged
    assert result.accepted == []

    # Le canonique doit avoir été mis à jour
    assert canonical.scanned_at == datetime(2026, 3, 21, 13, 30, 0)
    assert canonical.scan_method == "NFC_PHYSICAL"

    # L'history entry doit être marquée MERGED_OLDEST
    history_obj = db.add.call_args_list[0][0][0]
    assert isinstance(history_obj, AttendanceHistory)
    assert history_obj.merge_status == "MERGED_OLDEST"

    # Aucun nouvel objet Attendance créé (seulement history)
    assert db.add.call_count == 1


@patch(_PATCH, return_value=[])
def test_scan_plus_ancien_aware_vs_naive(_):
    """Fusion fonctionne même avec timestamps aware vs naive."""
    canonical = make_canonical(scanned_at=datetime(2026, 3, 21, 14, 0, 0))

    scan = make_scan(
        scanned_at=datetime(2026, 3, 21, 13, 30, 0, tzinfo=timezone.utc),
    )
    db = make_db(None, canonical)

    result = sync_attendances(db, scans=[scan])

    assert result.total_merged == 1
    assert str(scan.client_uuid) in result.merged


# ================================================================
# Supersession : scan plus récent → canonique conservé
# ================================================================

@patch(_PATCH, return_value=[])
def test_scan_plus_recent_supersede(_):
    """
    2e enseignant synchronise un scan plus récent → SUPERSEDED.
    Le canonique (plus ancien) est conservé tel quel.
    """
    canonical = make_canonical(scanned_at=datetime(2026, 3, 21, 10, 0, 0))

    # Nouveau scan à 14:00 (plus récent que le canonique à 10:00)
    scan = make_scan(scanned_at=datetime(2026, 3, 21, 14, 0, 0))
    db = make_db(None, canonical)

    result = sync_attendances(db, scans=[scan])

    assert result.total_inserted == 0
    assert result.total_merged == 0
    assert result.accepted == []
    assert result.merged == []

    # Canonique inchangé
    assert canonical.scanned_at == datetime(2026, 3, 21, 10, 0, 0)

    # History archivée comme SUPERSEDED
    history_obj = db.add.call_args_list[0][0][0]
    assert history_obj.merge_status == "SUPERSEDED"

    # Aucun Attendance ajouté
    assert db.add.call_count == 1


@patch(_PATCH, return_value=[])
def test_meme_timestamp_pas_de_remplacement(_):
    """Timestamps identiques → canonical conservé (pas de fusion à égalité)."""
    ts = datetime(2026, 3, 21, 12, 0, 0)
    canonical = make_canonical(scanned_at=ts)

    scan = make_scan(scanned_at=ts)
    db = make_db(None, canonical)

    result = sync_attendances(db, scans=[scan])

    assert result.total_merged == 0
    assert result.total_inserted == 0
    # History SUPERSEDED (pas strictement plus ancien)
    history_obj = db.add.call_args_list[0][0][0]
    assert history_obj.merge_status == "SUPERSEDED"


# ================================================================
# Plusieurs conflits dans le même batch
# ================================================================

@patch(_PATCH, return_value=[])
def test_plusieurs_conflits_batch(_):
    """
    Batch avec 3 scans pour 2 étudiants différents :
    - Étudiant A : scan plus ancien → MERGED_OLDEST
    - Étudiant B : scan plus récent → SUPERSEDED
    - Étudiant C : nouveau → ACCEPTED
    """
    canonical_a = make_canonical(scanned_at=datetime(2026, 3, 21, 14, 0, 0))
    canonical_b = make_canonical(scanned_at=datetime(2026, 3, 21, 10, 0, 0))

    scan_a = make_scan(scanned_at=datetime(2026, 3, 21, 13, 0, 0))  # plus ancien
    scan_b = make_scan(scanned_at=datetime(2026, 3, 21, 15, 0, 0))  # plus récent
    scan_c = make_scan()  # nouveau (pas de canonical)

    # Ordre execute : a-history=None, a-canonical=canonical_a,
    #                 b-history=None, b-canonical=canonical_b,
    #                 c-history=None, c-canonical=None
    db = make_db(None, canonical_a, None, canonical_b, None, None)

    result = sync_attendances(db, scans=[scan_a, scan_b, scan_c])

    assert result.total_received == 3
    assert result.total_inserted == 1   # scan_c
    assert result.total_merged == 1     # scan_a
    assert len(result.merged) == 1
    assert len(result.accepted) == 1
    assert str(scan_a.client_uuid) in result.merged
    assert str(scan_c.client_uuid) in result.accepted


# ================================================================
# Vérification du champ scanned_by sur la fusion
# ================================================================

@patch(_PATCH, return_value=[])
def test_scanned_by_mis_a_jour_sur_fusion(_):
    """Quand fusion MERGED_OLDEST, scanned_by du canonique est mis à jour."""
    teacher_id = uuid.uuid4()
    canonical = make_canonical(scanned_at=datetime(2026, 3, 21, 14, 0, 0))

    scan = make_scan(scanned_at=datetime(2026, 3, 21, 13, 0, 0))
    db = make_db(None, canonical)

    sync_attendances(db, scans=[scan], scanned_by=teacher_id)

    assert canonical.scanned_by == teacher_id


# ================================================================
# device_id transmis dans l'historique
# ================================================================

@patch(_PATCH, return_value=[])
def test_device_id_dans_history(_):
    """device_id est bien enregistré dans AttendanceHistory."""
    db = make_db(None, None)
    scan = make_scan()

    sync_attendances(db, scans=[scan], device_id="device-teacher-42")

    history_obj = db.add.call_args_list[0][0][0]
    assert history_obj.device_id == "device-teacher-42"


# ================================================================
# Détection d'anomalies temporelles (_detect_temporal_anomalies)
# ================================================================

def make_row(scanned_at: datetime, seq: int, name: str):
    """Simule une ligne (scanned_at, sequence_order, name) retournée par SQLAlchemy."""
    return (scanned_at, seq, name)


def test_detection_anomalie_simple():
    """Élève scanné au CP2 (seq=2) avant CP1 (seq=1) → 1 anomalie détectée."""
    student_id = uuid.uuid4()
    trip_id = uuid.uuid4()

    scan = ScanItem(
        client_uuid=uuid.uuid4(),
        student_id=student_id,
        trip_id=trip_id,
        checkpoint_id=uuid.uuid4(),
        scanned_at=datetime(2026, 3, 21, 12, 0, 0),
        scan_method="NFC_PHYSICAL",
    )

    db = MagicMock()
    # CP1 à 13:00, CP2 à 10:00 (CP2 avant CP1 → anomalie)
    rows = [
        make_row(datetime(2026, 3, 21, 13, 0, 0), 1, "Départ bus"),
        make_row(datetime(2026, 3, 21, 10, 0, 0), 2, "Entrée musée"),
    ]
    result_mock = MagicMock()
    result_mock.all.return_value = rows
    db.execute.return_value = result_mock

    anomalies = _detect_temporal_anomalies(db, [scan])

    assert len(anomalies) == 1
    assert anomalies[0].checkpoint_before == "Départ bus"
    assert anomalies[0].checkpoint_after == "Entrée musée"
    assert "Incohérence temporelle" in anomalies[0].description


def test_pas_anomalie_si_ordre_correct():
    """Timestamps croissants → aucune anomalie."""
    student_id = uuid.uuid4()
    trip_id = uuid.uuid4()

    scan = ScanItem(
        client_uuid=uuid.uuid4(),
        student_id=student_id,
        trip_id=trip_id,
        checkpoint_id=uuid.uuid4(),
        scanned_at=datetime(2026, 3, 21, 12, 0, 0),
        scan_method="QR_PHYSICAL",
    )

    db = MagicMock()
    rows = [
        make_row(datetime(2026, 3, 21, 10, 0, 0), 1, "CP1"),
        make_row(datetime(2026, 3, 21, 12, 0, 0), 2, "CP2"),
        make_row(datetime(2026, 3, 21, 14, 0, 0), 3, "CP3"),
    ]
    result_mock = MagicMock()
    result_mock.all.return_value = rows
    db.execute.return_value = result_mock

    anomalies = _detect_temporal_anomalies(db, [scan])

    assert anomalies == []


def test_pas_anomalie_si_un_seul_checkpoint():
    """Un seul checkpoint → pas de comparaison possible, aucune anomalie."""
    scan = ScanItem(
        client_uuid=uuid.uuid4(),
        student_id=uuid.uuid4(),
        trip_id=uuid.uuid4(),
        checkpoint_id=uuid.uuid4(),
        scanned_at=datetime(2026, 3, 21, 12, 0, 0),
        scan_method="NFC_PHYSICAL",
    )

    db = MagicMock()
    result_mock = MagicMock()
    result_mock.all.return_value = [make_row(datetime(2026, 3, 21, 12, 0, 0), 1, "CP1")]
    db.execute.return_value = result_mock

    anomalies = _detect_temporal_anomalies(db, [scan])

    assert anomalies == []


def test_batch_vide_retourne_liste_vide():
    """Batch vide → _detect_temporal_anomalies retourne [] sans requête DB."""
    db = MagicMock()
    anomalies = _detect_temporal_anomalies(db, [])
    assert anomalies == []
    db.execute.assert_not_called()


def test_anomalie_fields_complets():
    """Vérifier que tous les champs de TemporalAnomaly sont renseignés."""
    student_id = uuid.uuid4()
    trip_id = uuid.uuid4()

    scan = ScanItem(
        client_uuid=uuid.uuid4(),
        student_id=student_id,
        trip_id=trip_id,
        checkpoint_id=uuid.uuid4(),
        scanned_at=datetime(2026, 3, 21, 12, 0, 0),
        scan_method="NFC_PHYSICAL",
    )

    db = MagicMock()
    rows = [
        make_row(datetime(2026, 3, 21, 14, 0, 0), 1, "CP Départ"),
        make_row(datetime(2026, 3, 21, 11, 0, 0), 2, "CP Arrivée"),
    ]
    result_mock = MagicMock()
    result_mock.all.return_value = rows
    db.execute.return_value = result_mock

    anomalies = _detect_temporal_anomalies(db, [scan])

    assert len(anomalies) == 1
    a = anomalies[0]
    assert a.student_id == str(student_id)
    assert a.trip_id == str(trip_id)
    assert a.checkpoint_before == "CP Départ"
    assert a.checkpoint_after == "CP Arrivée"
    assert "2026-03-21T14:00:00" in a.scanned_at_before
    assert "2026-03-21T11:00:00" in a.scanned_at_after
