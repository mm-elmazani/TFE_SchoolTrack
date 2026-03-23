"""
Service de synchronisation offline → online (US 3.1 + US 3.2).

Stratégie US 3.2 — Fusion multi-enseignants :
- attendance_history : archive TOUS les scans bruts reçus (append-only par client_uuid)
- attendances        : table canonique, UNE ligne par (student, checkpoint, trip)
                       = le scan avec le timestamp le plus ancien (premier arrivé réel)
- Idempotence        : client_uuid unique dans attendance_history
- Fusion             : si nouvel arrivant a scanned_at < canonique existant → mise à jour
- Anomalies          : détection des incohérences d'ordre entre checkpoints
"""

import logging
import uuid as uuid_module
from datetime import datetime
from typing import List

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.attendance import Attendance, AttendanceHistory
from app.models.checkpoint import Checkpoint
from app.models.sync_log import SyncLog
from app.schemas.sync import ScanItem, SyncResponse, TemporalAnomaly

logger = logging.getLogger(__name__)

_ACCEPTED       = "ACCEPTED"       # Premier scan → inséré comme canonique
_MERGED_OLDEST  = "MERGED_OLDEST"  # Scan plus ancien → a remplacé le canonique
_SUPERSEDED     = "SUPERSEDED"     # Scan plus récent → canonique (plus ancien) conservé


def sync_attendances(
    db: Session,
    scans: List[ScanItem],
    device_id: str = "",
    scanned_by: uuid_module.UUID | None = None,
) -> SyncResponse:
    """
    Reçoit un batch de scans et les fusionne intelligemment (US 3.2).

    Pour chaque scan :
    1. Vérifie que client_uuid n'est pas un doublon (intra-batch ou déjà en history)
    2. Insère dans attendance_history (archive brute)
    3. UPSERT dans attendances (canonique) :
       - Nouveau (student, checkpoint) → INSERT
       - Existant ET nouveau plus ancien → UPDATE (fusion)
       - Existant ET nouveau plus récent → aucun changement canonique (SUPERSEDED)
    4. Détecte les anomalies temporelles entre checkpoints
    """
    accepted: List[str] = []
    duplicate: List[str] = []
    merged: List[str] = []
    rejected: List[str] = []

    seen_in_batch: set = set()
    # Cache des checkpoint_ids valides (evite N requetes pour le meme checkpoint)
    valid_checkpoints: dict[uuid_module.UUID, bool] = {}
    # Cache des canoniques crees dans ce batch (evite le doublon intra-batch
    # quand 2 scans du meme (student, checkpoint, trip) ont des client_uuid differents)
    batch_canonicals: dict[tuple, "Attendance"] = {}
    sync_session_id = uuid_module.uuid4()

    for scan in scans:
        client_uuid_str = str(scan.client_uuid)

        # 1. Doublon intra-batch (même UUID deux fois dans le même envoi)
        if scan.client_uuid in seen_in_batch:
            duplicate.append(client_uuid_str)
            continue

        # 2. Doublon inter-batch : client_uuid déjà archivé en history
        already_known = db.execute(
            select(AttendanceHistory).where(
                AttendanceHistory.client_uuid == scan.client_uuid
            )
        ).scalar()

        if already_known:
            duplicate.append(client_uuid_str)
            seen_in_batch.add(scan.client_uuid)
            continue

        # 2b. Vérifier que le checkpoint existe toujours en DB
        if scan.checkpoint_id not in valid_checkpoints:
            cp_exists = db.execute(
                select(Checkpoint.id).where(Checkpoint.id == scan.checkpoint_id)
            ).scalar() is not None
            valid_checkpoints[scan.checkpoint_id] = cp_exists

        if not valid_checkpoints[scan.checkpoint_id]:
            rejected.append(client_uuid_str)
            seen_in_batch.add(scan.client_uuid)
            logger.warning(
                "Scan %s rejeté : checkpoint %s supprimé",
                client_uuid_str, scan.checkpoint_id,
            )
            continue

        # 3. Insérer dans l'historique brut (toujours, sauf doublon UUID)
        history = AttendanceHistory(
            client_uuid=scan.client_uuid,
            trip_id=scan.trip_id,
            checkpoint_id=scan.checkpoint_id,
            student_id=scan.student_id,
            scanned_at=scan.scanned_at,
            scanned_by=scanned_by,
            scan_method=scan.scan_method,
            scan_sequence=scan.scan_sequence,
            is_manual=scan.is_manual,
            justification=scan.justification,
            comment=scan.comment,
            device_id=device_id,
            sync_session_id=sync_session_id,
            merge_status=_ACCEPTED,
        )
        db.add(history)

        # 4. Chercher le canonique existant pour (student, checkpoint, trip)
        #    D'abord dans le cache intra-batch, puis en DB
        canon_key = (scan.student_id, scan.checkpoint_id, scan.trip_id)
        canonical = batch_canonicals.get(canon_key)
        if canonical is None:
            canonical = db.execute(
                select(Attendance).where(
                    Attendance.student_id == scan.student_id,
                    Attendance.checkpoint_id == scan.checkpoint_id,
                    Attendance.trip_id == scan.trip_id,
                )
            ).scalar()

        if canonical is None:
            # Aucun scan precedent pour cet eleve a ce checkpoint → creer le canonique
            attendance = Attendance(
                client_uuid=scan.client_uuid,
                trip_id=scan.trip_id,
                checkpoint_id=scan.checkpoint_id,
                student_id=scan.student_id,
                scanned_at=scan.scanned_at,
                scanned_by=scanned_by,
                scan_method=scan.scan_method,
                scan_sequence=scan.scan_sequence,
                is_manual=scan.is_manual,
                justification=scan.justification,
                comment=scan.comment,
            )
            db.add(attendance)
            batch_canonicals[canon_key] = attendance
            accepted.append(client_uuid_str)
            logger.debug("Nouveau canonique : student=%s, cp=%s", scan.student_id, scan.checkpoint_id)

        elif _is_strictly_older(scan.scanned_at, canonical.scanned_at):
            # Nouveau scan plus ancien → remplace le canonique (on garde le plus ancien)
            canonical.client_uuid = scan.client_uuid
            canonical.scanned_at = scan.scanned_at
            canonical.scanned_by = scanned_by
            canonical.scan_method = scan.scan_method
            canonical.scan_sequence = scan.scan_sequence
            canonical.is_manual = scan.is_manual
            canonical.justification = scan.justification
            canonical.comment = scan.comment
            history.merge_status = _MERGED_OLDEST
            merged.append(client_uuid_str)
            logger.info(
                "Fusion : scan %s plus ancien → remplace canonique (student=%s, cp=%s)",
                client_uuid_str, scan.student_id, scan.checkpoint_id,
            )

        else:
            # Scan plus récent ou même timestamp → canonique existant déjà optimal
            history.merge_status = _SUPERSEDED
            logger.debug(
                "Scan %s supersédé : canonique déjà plus ancien (student=%s, cp=%s)",
                client_uuid_str, scan.student_id, scan.checkpoint_id,
            )

        seen_in_batch.add(scan.client_uuid)

    db.flush()

    # 5. Détecter les anomalies temporelles après la fusion canonique
    anomalies = _detect_temporal_anomalies(db, scans)

    # 6. Enregistrer dans sync_logs
    has_failures = len(rejected) > 0
    status = "SUCCESS" if not has_failures and not anomalies else "PARTIAL"
    trip_ids = {scan.trip_id for scan in scans}
    sync_log = SyncLog(
        user_id=scanned_by,
        trip_id=next(iter(trip_ids)) if len(trip_ids) == 1 else None,
        device_id=device_id or None,
        records_synced=len(accepted) + len(merged),
        conflicts_detected=len(duplicate) + len(rejected),
        status=status,
        error_details={
            "total_received": len(scans),
            "accepted": len(accepted),
            "merged": len(merged),
            "duplicate": len(duplicate),
            "rejected": len(rejected),
            "anomalies": len(anomalies),
        },
    )
    db.add(sync_log)

    db.commit()

    logger.info(
        "Sync device=%s : %d reçus, %d insérés, %d fusionnés, %d doublons, %d rejetés, %d anomalies",
        device_id or "inconnu",
        len(scans), len(accepted), len(merged), len(duplicate), len(rejected), len(anomalies),
    )

    return SyncResponse(
        accepted=accepted,
        duplicate=duplicate,
        merged=merged,
        rejected=rejected,
        temporal_anomalies=anomalies,
        total_received=len(scans),
        total_inserted=len(accepted),
        total_merged=len(merged),
    )


# ----------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------

def _is_strictly_older(new_dt: datetime, existing_dt: datetime) -> bool:
    """Retourne True si new_dt est strictement antérieur à existing_dt."""
    # Normaliser naive/aware pour éviter TypeError
    if new_dt.tzinfo is not None and existing_dt.tzinfo is None:
        new_dt = new_dt.replace(tzinfo=None)
    elif new_dt.tzinfo is None and existing_dt.tzinfo is not None:
        existing_dt = existing_dt.replace(tzinfo=None)
    return new_dt < existing_dt


def _detect_temporal_anomalies(
    db: Session,
    scans: List[ScanItem],
) -> List[TemporalAnomaly]:
    """
    Détecte les incohérences temporelles entre checkpoints pour les élèves synchronisés.

    Règle : pour un élève et un voyage, scanned_at(CP A) doit être < scanned_at(CP B)
    si sequence_order(A) < sequence_order(B).

    Signale mais ne bloque pas — les anomalies sont retournées dans le rapport.
    """
    if not scans:
        return []

    # Paires (student_id, trip_id) uniques du batch
    student_trips = {(scan.student_id, scan.trip_id) for scan in scans}
    anomalies: List[TemporalAnomaly] = []

    for student_id, trip_id in student_trips:
        rows = db.execute(
            select(
                Attendance.scanned_at,
                Checkpoint.sequence_order,
                Checkpoint.name,
            )
            .join(Checkpoint, Attendance.checkpoint_id == Checkpoint.id)
            .where(
                Attendance.student_id == student_id,
                Attendance.trip_id == trip_id,
            )
            .order_by(Checkpoint.sequence_order)
        ).all()

        if len(rows) < 2:
            continue

        for i in range(1, len(rows)):
            prev_at, prev_seq, prev_name = rows[i - 1]
            curr_at, curr_seq, curr_name = rows[i]

            # Normaliser naive/aware
            if prev_at.tzinfo is not None:
                prev_at = prev_at.replace(tzinfo=None)
            if curr_at.tzinfo is not None:
                curr_at = curr_at.replace(tzinfo=None)

            if curr_at < prev_at:
                anomalies.append(TemporalAnomaly(
                    student_id=str(student_id),
                    trip_id=str(trip_id),
                    checkpoint_before=prev_name,
                    checkpoint_after=curr_name,
                    scanned_at_before=prev_at.isoformat(),
                    scanned_at_after=curr_at.isoformat(),
                    description=(
                        f"Incohérence temporelle : checkpoint '{curr_name}' "
                        f"(ordre {curr_seq}) scanné avant '{prev_name}' (ordre {prev_seq})"
                    ),
                ))

    return anomalies
