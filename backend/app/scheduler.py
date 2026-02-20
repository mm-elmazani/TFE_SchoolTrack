"""
Planificateur APScheduler pour l'envoi automatique des QR codes 48h avant chaque voyage (US 1.6).

Le job s'exécute toutes les heures et envoie les QR codes aux élèves
dont le voyage est prévu dans exactement 2 jours (J+2), si ce n'est pas déjà fait.
"""

import logging
from datetime import date, timedelta

from apscheduler.schedulers.background import BackgroundScheduler
from sqlalchemy import select

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


def start_scheduler() -> None:
    """Démarre le planificateur en arrière-plan (appelé au démarrage de l'API)."""
    scheduler.add_job(
        _send_qr_emails_scheduled,
        trigger="interval",
        hours=1,
        id="qr_email_48h_check",
        replace_existing=True,
    )
    scheduler.start()
    logger.info("Scheduler démarré — vérification QR emails toutes les heures.")


def stop_scheduler() -> None:
    """Arrête le planificateur proprement (appelé à l'arrêt de l'API)."""
    if scheduler.running:
        scheduler.shutdown(wait=False)
        logger.info("Scheduler arrêté.")
