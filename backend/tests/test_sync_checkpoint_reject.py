"""
Tests unitaires — rejet de scans avec checkpoint supprimé + cache batch_canonicals.

Scénarios couverts :
- Scan avec checkpoint inexistant → rejeté (REJECTED)
- Plusieurs scans du même checkpoint supprimé → cache évite N requêtes
- Mix : checkpoint valide + checkpoint supprimé dans le même batch
- Cache batch_canonicals : 2 scans du même (student, checkpoint, trip) avec UUIDs différents
- SyncLog insertion après chaque sync
"""

import uuid
from datetime import datetime, timezone
from unittest.mock import MagicMock, call, patch

import pytest

from app.models.attendance import Attendance, AttendanceHistory
from app.models.sync_log import SyncLog
from app.schemas.sync import ScanItem
from app.services.sync_service import sync_attendances


# ----------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------

def make_scan(
    client_uuid=None,
    student_id=None,
    checkpoint_id=None,
    trip_id=None,
    scanned_at=None,
    scan_method="NFC_PHYSICAL",
) -> ScanItem:
    return ScanItem(
        client_uuid=client_uuid or uuid.uuid4(),
        student_id=student_id or uuid.uuid4(),
        checkpoint_id=checkpoint_id or uuid.uuid4(),
        trip_id=trip_id or uuid.uuid4(),
        scanned_at=scanned_at or datetime(2026, 3, 23, 10, 0, 0, tzinfo=timezone.utc),
        scan_method=scan_method,
    )


def make_execute_result(scalar_value):
    """Mock d'un résultat db.execute() avec scalar() prédéfini."""
    r = MagicMock()
    r.scalar.return_value = scalar_value
    return r


_PATCH = "app.services.sync_service._detect_temporal_anomalies"


# ================================================================
# Rejet de scans avec checkpoint supprimé
# ================================================================

class TestCheckpointReject:
    """Tests pour la validation de l'existence du checkpoint."""

    @patch(_PATCH, return_value=[])
    def test_scan_checkpoint_supprime_rejete(self, _):
        """Scan avec checkpoint inexistant → rejeté, pas d'insertion."""
        db = MagicMock()
        # Séquence execute : history=None, checkpoint=None (inexistant)
        db.execute.side_effect = [
            make_execute_result(None),   # history check → pas de doublon
            make_execute_result(None),   # checkpoint check → inexistant
        ] + [make_execute_result(None)] * 10

        scan = make_scan()
        result = sync_attendances(db, scans=[scan])

        assert result.total_received == 1
        assert result.total_inserted == 0
        assert len(result.rejected) == 1
        assert str(scan.client_uuid) in result.rejected
        assert result.accepted == []
        # Seul le SyncLog est ajouté (pas d'history ni de canonical)
        added_objects = [c[0][0] for c in db.add.call_args_list]
        assert not any(isinstance(o, AttendanceHistory) for o in added_objects)
        assert not any(isinstance(o, Attendance) for o in added_objects)

    @patch(_PATCH, return_value=[])
    def test_plusieurs_scans_meme_checkpoint_supprime_cache(self, _):
        """2 scans du même checkpoint supprimé → 1 seule requête checkpoint, 2 rejetés."""
        cp_id = uuid.uuid4()
        scan1 = make_scan(checkpoint_id=cp_id)
        scan2 = make_scan(checkpoint_id=cp_id)

        db = MagicMock()
        # scan1: history=None, checkpoint=None (inexistant)
        # scan2: history=None (checkpoint déjà en cache → pas de requête checkpoint)
        db.execute.side_effect = [
            make_execute_result(None),   # scan1 history
            make_execute_result(None),   # scan1 checkpoint → None
            make_execute_result(None),   # scan2 history
            # PAS de checkpoint check pour scan2 (cache)
        ] + [make_execute_result(None)] * 10

        result = sync_attendances(db, scans=[scan1, scan2])

        assert len(result.rejected) == 2
        assert result.total_inserted == 0

    @patch(_PATCH, return_value=[])
    def test_mix_checkpoint_valide_et_supprime(self, _):
        """Batch avec 1 scan valide + 1 scan checkpoint supprimé → 1 accepté, 1 rejeté."""
        cp_valid = uuid.uuid4()
        cp_deleted = uuid.uuid4()
        scan_ok = make_scan(checkpoint_id=cp_valid)
        scan_ko = make_scan(checkpoint_id=cp_deleted)

        db = MagicMock()
        # scan_ok: history=None, checkpoint=cp_valid (existe), canonical=None
        # scan_ko: history=None, checkpoint=None (supprimé)
        db.execute.side_effect = [
            make_execute_result(None),      # scan_ok history
            make_execute_result(cp_valid),   # scan_ok checkpoint → existe
            make_execute_result(None),      # scan_ok canonical → None (nouveau)
            make_execute_result(None),      # scan_ko history
            make_execute_result(None),      # scan_ko checkpoint → None (supprimé)
        ] + [make_execute_result(None)] * 10

        result = sync_attendances(db, scans=[scan_ok, scan_ko])

        assert result.total_inserted == 1
        assert len(result.accepted) == 1
        assert len(result.rejected) == 1
        assert str(scan_ok.client_uuid) in result.accepted
        assert str(scan_ko.client_uuid) in result.rejected

    @patch(_PATCH, return_value=[])
    def test_checkpoint_valide_passe_normalement(self, _):
        """Scan avec checkpoint existant → accepté normalement."""
        cp_id = uuid.uuid4()
        scan = make_scan(checkpoint_id=cp_id)

        db = MagicMock()
        db.execute.side_effect = [
            make_execute_result(None),    # history check
            make_execute_result(cp_id),   # checkpoint check → existe
            make_execute_result(None),    # canonical check → nouveau
        ] + [make_execute_result(None)] * 10

        result = sync_attendances(db, scans=[scan])

        assert result.total_inserted == 1
        assert len(result.accepted) == 1
        assert result.rejected == []


# ================================================================
# Cache batch_canonicals : dédup intra-batch (student, checkpoint, trip)
# ================================================================

class TestBatchCanonicals:
    """Tests pour le cache intra-batch qui évite les doublons canoniques."""

    @patch(_PATCH, return_value=[])
    def test_deux_scans_meme_student_checkpoint_trip_uuid_different(self, _):
        """
        2 scans (student, checkpoint, trip) identiques mais client_uuid différents.
        → 1 canonical créé (premier scan), le second est traité comme fusion/supersession.
        Pas de doublon INSERT grâce au cache batch_canonicals.
        """
        student_id = uuid.uuid4()
        cp_id = uuid.uuid4()
        trip_id = uuid.uuid4()

        scan1 = make_scan(
            student_id=student_id,
            checkpoint_id=cp_id,
            trip_id=trip_id,
            scanned_at=datetime(2026, 3, 23, 10, 0, 0),
        )
        scan2 = make_scan(
            student_id=student_id,
            checkpoint_id=cp_id,
            trip_id=trip_id,
            scanned_at=datetime(2026, 3, 23, 10, 30, 0),  # Plus récent
        )

        db = MagicMock()
        # scan1: history=None, checkpoint=existe, canonical=None (nouveau)
        # scan2: history=None, checkpoint (cache → pas de requête), canonical (cache → pas de requête DB)
        db.execute.side_effect = [
            make_execute_result(None),    # scan1 history
            make_execute_result(cp_id),   # scan1 checkpoint → existe
            make_execute_result(None),    # scan1 canonical → None
            make_execute_result(None),    # scan2 history
            # scan2 checkpoint → cache (pas d'execute pour checkpoint)
            # scan2 canonical → cache (pas d'execute pour canonical)
        ] + [make_execute_result(None)] * 10

        result = sync_attendances(db, scans=[scan1, scan2])

        # scan1 : accepté (nouveau canonical)
        # scan2 : ni accepté ni merged (SUPERSEDED car plus récent)
        assert result.total_received == 2
        assert result.total_inserted == 1
        assert len(result.accepted) == 1
        assert str(scan1.client_uuid) in result.accepted

    @patch(_PATCH, return_value=[])
    def test_deux_scans_meme_triplet_ancien_en_second(self, _):
        """
        2 scans (student, checkpoint, trip) identiques.
        Le second a un timestamp plus ancien → il remplace le canonical (MERGED_OLDEST).
        """
        student_id = uuid.uuid4()
        cp_id = uuid.uuid4()
        trip_id = uuid.uuid4()

        scan1 = make_scan(
            student_id=student_id,
            checkpoint_id=cp_id,
            trip_id=trip_id,
            scanned_at=datetime(2026, 3, 23, 14, 0, 0),  # Plus récent
        )
        scan2 = make_scan(
            student_id=student_id,
            checkpoint_id=cp_id,
            trip_id=trip_id,
            scanned_at=datetime(2026, 3, 23, 10, 0, 0),  # Plus ancien
        )

        db = MagicMock()
        db.execute.side_effect = [
            make_execute_result(None),    # scan1 history
            make_execute_result(cp_id),   # scan1 checkpoint → existe
            make_execute_result(None),    # scan1 canonical → None (nouveau)
            make_execute_result(None),    # scan2 history
        ] + [make_execute_result(None)] * 10

        result = sync_attendances(db, scans=[scan1, scan2])

        assert result.total_received == 2
        assert result.total_inserted == 1
        assert result.total_merged == 1
        assert str(scan1.client_uuid) in result.accepted
        assert str(scan2.client_uuid) in result.merged


# ================================================================
# Insertion SyncLog
# ================================================================

class TestSyncLogInsertion:
    """Tests pour l'insertion automatique dans sync_logs."""

    @patch(_PATCH, return_value=[])
    def test_synclog_insere_apres_sync(self, _):
        """Un SyncLog est ajouté après chaque synchronisation."""
        db = MagicMock()
        cp_id = uuid.uuid4()
        db.execute.side_effect = [
            make_execute_result(None),    # history
            make_execute_result(cp_id),   # checkpoint
            make_execute_result(None),    # canonical
        ] + [make_execute_result(None)] * 10

        scan = make_scan(checkpoint_id=cp_id)
        teacher_id = uuid.uuid4()
        sync_attendances(db, scans=[scan], device_id="device-01", scanned_by=teacher_id)

        # Trouver le SyncLog parmi les objets ajoutés
        added = [c[0][0] for c in db.add.call_args_list]
        sync_logs = [o for o in added if isinstance(o, SyncLog)]
        assert len(sync_logs) == 1

        sl = sync_logs[0]
        assert sl.user_id == teacher_id
        assert sl.device_id == "device-01"
        assert sl.records_synced == 1
        assert sl.status == "SUCCESS"
        assert sl.error_details is not None
        assert sl.error_details["accepted"] == 1

    @patch(_PATCH, return_value=[])
    def test_synclog_status_partial_si_rejets(self, _):
        """SyncLog status=PARTIAL quand des scans sont rejetés."""
        db = MagicMock()
        # Scan avec checkpoint supprimé
        db.execute.side_effect = [
            make_execute_result(None),   # history
            make_execute_result(None),   # checkpoint → supprimé
        ] + [make_execute_result(None)] * 10

        scan = make_scan()
        sync_attendances(db, scans=[scan])

        added = [c[0][0] for c in db.add.call_args_list]
        sync_logs = [o for o in added if isinstance(o, SyncLog)]
        assert len(sync_logs) == 1
        assert sync_logs[0].status == "PARTIAL"
        assert sync_logs[0].conflicts_detected == 1

    @patch(_PATCH, return_value=[])
    def test_synclog_batch_vide(self, _):
        """Batch vide → SyncLog quand même créé avec status SUCCESS."""
        db = MagicMock()
        db.execute.side_effect = [make_execute_result(None)] * 10

        sync_attendances(db, scans=[], device_id="device-vide")

        added = [c[0][0] for c in db.add.call_args_list]
        sync_logs = [o for o in added if isinstance(o, SyncLog)]
        assert len(sync_logs) == 1
        assert sync_logs[0].records_synced == 0
        assert sync_logs[0].status == "SUCCESS"

    @patch(_PATCH, return_value=[])
    def test_synclog_trip_id_unique(self, _):
        """Si tous les scans sont du même voyage → trip_id renseigné dans SyncLog."""
        trip_id = uuid.uuid4()
        cp_id = uuid.uuid4()
        scan1 = make_scan(trip_id=trip_id, checkpoint_id=cp_id)
        scan2 = make_scan(trip_id=trip_id, checkpoint_id=cp_id)

        db = MagicMock()
        db.execute.side_effect = [
            make_execute_result(None), make_execute_result(cp_id), make_execute_result(None),  # scan1
            make_execute_result(None),  # scan2 history (checkpoint+canonical en cache)
        ] + [make_execute_result(None)] * 10

        sync_attendances(db, scans=[scan1, scan2])

        added = [c[0][0] for c in db.add.call_args_list]
        sync_logs = [o for o in added if isinstance(o, SyncLog)]
        assert sync_logs[0].trip_id == trip_id

    @patch(_PATCH, return_value=[])
    def test_synclog_trip_id_none_si_multi_voyages(self, _):
        """Scans de voyages différents → trip_id=None dans SyncLog."""
        cp_id = uuid.uuid4()
        scan1 = make_scan(trip_id=uuid.uuid4(), checkpoint_id=cp_id)
        scan2 = make_scan(trip_id=uuid.uuid4(), checkpoint_id=cp_id)

        db = MagicMock()
        db.execute.side_effect = [
            make_execute_result(None), make_execute_result(cp_id), make_execute_result(None),  # scan1
            make_execute_result(None), make_execute_result(None),  # scan2 history + canonical
        ] + [make_execute_result(None)] * 10

        sync_attendances(db, scans=[scan1, scan2])

        added = [c[0][0] for c in db.add.call_args_list]
        sync_logs = [o for o in added if isinstance(o, SyncLog)]
        assert sync_logs[0].trip_id is None

    @patch(_PATCH, return_value=[])
    def test_synclog_error_details_complets(self, _):
        """error_details contient toutes les clés attendues."""
        db = MagicMock()
        db.execute.side_effect = [make_execute_result(None)] * 10

        sync_attendances(db, scans=[])

        added = [c[0][0] for c in db.add.call_args_list]
        sync_logs = [o for o in added if isinstance(o, SyncLog)]
        details = sync_logs[0].error_details
        assert "total_received" in details
        assert "accepted" in details
        assert "merged" in details
        assert "duplicate" in details
        assert "rejected" in details
        assert "anomalies" in details


# ================================================================
# Intégration : scénario complet
# ================================================================

class TestSyncScenarioComplet:
    """Scénarios end-to-end avec mix de tous les cas."""

    @patch(_PATCH, return_value=[])
    def test_batch_mixte_complet(self, _):
        """
        Batch de 5 scans :
        - scan1 : nouveau, checkpoint valide → ACCEPTED
        - scan2 : même UUID que scan1 → doublon intra-batch
        - scan3 : checkpoint supprimé → REJECTED
        - scan4 : déjà en history → doublon inter-batch
        - scan5 : nouveau, checkpoint valide → ACCEPTED
        """
        cp_valid = uuid.uuid4()
        cp_deleted = uuid.uuid4()
        shared_uuid = uuid.uuid4()

        scan1 = make_scan(client_uuid=shared_uuid, checkpoint_id=cp_valid)
        scan2 = make_scan(client_uuid=shared_uuid, checkpoint_id=cp_valid)  # Même UUID
        scan3 = make_scan(checkpoint_id=cp_deleted)
        scan4 = make_scan()
        scan5 = make_scan(checkpoint_id=cp_valid)

        existing_history = MagicMock(spec=AttendanceHistory)

        db = MagicMock()
        db.execute.side_effect = [
            # scan1: history=None, checkpoint=valid, canonical=None
            make_execute_result(None),
            make_execute_result(cp_valid),
            make_execute_result(None),
            # scan2: intra-batch dup → pas d'execute (skip direct)
            # scan3: history=None, checkpoint=None (supprimé)
            make_execute_result(None),
            make_execute_result(None),
            # scan4: history=existing → doublon
            make_execute_result(existing_history),
            # scan5: history=None, checkpoint (cache valid), canonical=None
            make_execute_result(None),
            make_execute_result(None),  # canonical
        ] + [make_execute_result(None)] * 10

        result = sync_attendances(db, scans=[scan1, scan2, scan3, scan4, scan5])

        assert result.total_received == 5
        assert result.total_inserted == 2  # scan1 + scan5
        assert len(result.accepted) == 2
        assert len(result.duplicate) == 2  # scan2 (intra) + scan4 (inter)
        assert len(result.rejected) == 1   # scan3
        assert str(scan3.client_uuid) in result.rejected
