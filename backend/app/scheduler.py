"""
Planificateur APScheduler (US 1.6, US 6.4).

Jobs :
- QR emails 48h avant chaque voyage (toutes les heures)
- Rotation des audit logs > 12 mois (tous les jours a 3h)
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
    scheduler.start()
    logger.info("Scheduler démarré — QR emails (1h) + rotation audit logs (3h quotidien).")


def stop_scheduler() -> None:
    """Arrête le planificateur proprement (appelé à l'arrêt de l'API)."""
    if scheduler.running:
        scheduler.shutdown(wait=False)
        logger.info("Scheduler arrêté.")
