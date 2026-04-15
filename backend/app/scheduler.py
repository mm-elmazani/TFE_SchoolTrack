"""
Planificateur APScheduler (US 1.6, US 6.4).

Jobs :
- QR emails 48h avant chaque voyage (toutes les heures)
- Rotation des audit logs > 12 mois (tous les jours a 3h)
- Transition automatique des statuts de voyages (toutes les 15 min)
"""

import logging
from datetime import date, datetime, timedelta

from apscheduler.schedulers.background import BackgroundScheduler
from sqlalchemy import select, text

from app.database import SessionLocal
from app.models.trip import Trip

logger = logging.getLogger(__name__)

scheduler = BackgroundScheduler()


def _send_qr_emails_scheduled() -> None:
    """
    Tâche planifiée : cherche les voyages dont la date est J+2 et déclenche
    l'envoi des QR codes pour les élèves non encore notifiés.
    Import local pour éviter les imports circulaires.
    """
    from app.services.qr_email_service import send_qr_emails_for_trip

    target_date = date.today() + timedelta(days=2)
    db = SessionLocal()
    try:
        trips = db.execute(
            select(Trip).where(
                Trip.date == target_date,
                Trip.status.in_(["PLANNED", "ACTIVE"]),
            )
        ).scalars().all()

        for trip in trips:
            logger.info(
                "Envoi automatique QR codes — voyage %s (%s, %s)",
                trip.id, trip.destination, trip.date,
            )
            result = send_qr_emails_for_trip(db, trip.id)
            logger.info(
                "Voyage %s : %d envoyés, %d déjà envoyés, %d sans email, %d erreurs",
                trip.id,
                result.sent_count,
                result.already_sent_count,
                result.no_email_count,
                len(result.errors),
            )
    except Exception as exc:
        logger.error("Erreur lors de l'envoi automatique des QR codes : %s", exc)
    finally:
        db.close()


def _purge_old_audit_logs() -> None:
    """
    Tache planifiee (US 6.4) : supprime les logs d'audit de plus de 12 mois.
    Conservation minimale de 12 mois pour conformite RGPD.
    """
    cutoff = datetime.utcnow() - timedelta(days=365)
    db = SessionLocal()
    try:
        result = db.execute(
            text("DELETE FROM audit_logs WHERE performed_at < :cutoff"),
            {"cutoff": cutoff},
        )
        deleted = result.rowcount
        db.commit()
        if deleted > 0:
            logger.info("Rotation audit logs : %d entrees supprimees (avant %s).", deleted, cutoff.date())
        else:
            logger.debug("Rotation audit logs : rien a supprimer.")
    except Exception as exc:
        db.rollback()
        logger.error("Erreur lors de la rotation des audit logs : %s", exc)
    finally:
        db.close()


def _auto_update_trip_statuses() -> None:
    """
    Tache planifiee : met a jour automatiquement le statut des voyages
    en fonction de la date du jour.
    - PLANNED + date == aujourd'hui  → ACTIVE
    - PLANNED + date <  aujourd'hui  → COMPLETED (rattrapage)
    - ACTIVE  → reste ACTIVE jusqu'à clôture manuelle par l'enseignant
      (un voyage peut durer plusieurs jours — pas de clôture automatique)
    """
    from app.services import assignment_service

    today = date.today()
    db = SessionLocal()
    try:
        # PLANNED → ACTIVE (date == aujourd'hui)
        planned_today = db.execute(
            select(Trip).where(
                Trip.status == "PLANNED",
                Trip.date == today,
            )
        ).scalars().all()

        for trip in planned_today:
            trip.status = "ACTIVE"
            logger.info(
                "Transition automatique PLANNED → ACTIVE — voyage %s (%s)",
                trip.id, trip.destination,
            )

        # PLANNED → COMPLETED (date < aujourd'hui, rattrapage)
        planned_past = db.execute(
            select(Trip).where(
                Trip.status == "PLANNED",
                Trip.date < today,
            )
        ).scalars().all()

        for trip in planned_past:
            trip.status = "COMPLETED"
            logger.info(
                "Transition automatique PLANNED → COMPLETED (rattrapage) — voyage %s (%s)",
                trip.id, trip.destination,
            )

        db.commit()

        # Liberer les bracelets des voyages termines (apres commit)
        for trip in planned_past:
            assignment_service.release_trip_tokens(db, trip.id)

        total = len(planned_today) + len(planned_past)
        if total > 0:
            logger.info(
                "Transition statuts : %d PLANNED→ACTIVE, %d PLANNED→COMPLETED.",
                len(planned_today), len(planned_past),
            )
        else:
            logger.debug("Transition statuts : aucun voyage a mettre a jour.")
    except Exception as exc:
        db.rollback()
        logger.error("Erreur lors de la transition automatique des statuts : %s", exc)
    finally:
        db.close()


def start_scheduler() -> None:
    """Démarre le planificateur en arrière-plan (appelé au démarrage de l'API)."""
    scheduler.add_job(
        _send_qr_emails_scheduled,
        trigger="interval",
        hours=1,
        id="qr_email_48h_check",
        replace_existing=True,
    )
    scheduler.add_job(
        _purge_old_audit_logs,
        trigger="cron",
        hour=3,
        minute=0,
        id="audit_log_rotation",
        replace_existing=True,
    )
    scheduler.add_job(
        _auto_update_trip_statuses,
        trigger="interval",
        minutes=15,
        id="trip_status_auto_update",
        replace_existing=True,
    )
    scheduler.start()
    logger.info("Scheduler démarré — QR emails (1h) + rotation audit logs (3h quotidien) + statuts voyages (15min).")


def stop_scheduler() -> None:
    """Arrête le planificateur proprement (appelé à l'arrêt de l'API)."""
    if scheduler.running:
        scheduler.shutdown(wait=False)
        logger.info("Scheduler arrêté.")
