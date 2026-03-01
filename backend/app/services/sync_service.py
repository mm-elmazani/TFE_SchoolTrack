"""
Service de synchronisation offline → online (US 3.1).

Stratégie : Hybride (LWW + CRDT append-only)
- Les scans sont append-only : chaque scan a un client_uuid unique → pas de conflit possible
- Idempotence via client_uuid : un UUID déjà connu est silencieusement ignoré
- Doublons intra-batch gérés en mémoire (autoflush=False)
- En cas de 2 enseignants qui scannent le même élève au même checkpoint :
  les 2 scans ont des UUIDs différents → tous les 2 sont insérés (append-only)
"""

import logging
import uuid as uuid_module
from typing import List

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.attendance import Attendance
from app.schemas.sync import ScanItem, SyncResponse

logger = logging.getLogger(__name__)


def sync_attendances(
    db: Session,
    scans: List[ScanItem],
    device_id: str = "",
) -> SyncResponse:
    """
    Insère en batch les scans reçus depuis un appareil Flutter.

    Pour chaque scan :
    1. Vérifie que client_uuid n'a pas déjà été reçu dans CE batch (set en mémoire)
    2. Vérifie que client_uuid n'existe pas déjà en base de données
    3. Si nouveau → crée l'enregistrement Attendance
    4. Si doublon → l'ajoute à la liste `duplicate` (aucune erreur levée)

    Toute la transaction est commitée en une seule fois.
    """
    accepted: List[str] = []
    duplicate: List[str] = []

    # Ensemble des UUIDs déjà traités dans CE batch (protection contre doublons intra-batch)
    # Nécessaire car autoflush=False → les INSERTs en attente ne sont pas visibles via SELECT
    seen_in_batch: set = set()

    for scan in scans:
        client_uuid_str = str(scan.client_uuid)

        # 1. Doublon intra-batch
        if scan.client_uuid in seen_in_batch:
            duplicate.append(client_uuid_str)
            logger.debug("Doublon intra-batch ignoré : %s", client_uuid_str)
            continue

        # 2. Doublon inter-batch (déjà en base)
        existing = db.execute(
            select(Attendance).where(Attendance.client_uuid == scan.client_uuid)
        ).scalar()

        if existing:
            duplicate.append(client_uuid_str)
            logger.debug("UUID déjà synchronisé, ignoré : %s", client_uuid_str)
            continue

        # 3. Nouveau scan → insérer
        attendance = Attendance(
            client_uuid=scan.client_uuid,
            trip_id=scan.trip_id,
            checkpoint_id=scan.checkpoint_id,
            student_id=scan.student_id,
            scanned_at=scan.scanned_at,
            scan_method=scan.scan_method,
            scan_sequence=scan.scan_sequence,
            is_manual=scan.is_manual,
            justification=scan.justification,
            comment=scan.comment,
        )
        db.add(attendance)
        seen_in_batch.add(scan.client_uuid)
        accepted.append(client_uuid_str)

    db.commit()

    logger.info(
        "Sync device=%s : %d reçus, %d insérés, %d doublons",
        device_id or "inconnu", len(scans), len(accepted), len(duplicate),
    )

    return SyncResponse(
        accepted=accepted,
        duplicate=duplicate,
        total_received=len(scans),
        total_inserted=len(accepted),
    )
