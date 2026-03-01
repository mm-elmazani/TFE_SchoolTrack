"""
Service d'orchestration pour l'envoi des QR codes digitaux par email (US 1.6).

Flux :
  1. Vérifier que le voyage existe et n'est pas archivé
  2. Pour chaque élève inscrit au voyage :
     a. Skip si pas d'email
     b. Skip si déjà une assignation active sur ce voyage (NFC, QR physique ou QR digital)
     c. Générer un token_uid unique (QRD-XXXXXXXX)
     d. Générer l'image QR code en mémoire
     e. Envoyer l'email (l'assignation n'est créée qu'en cas de succès)
  3. Persister toutes les assignations créées et retourner le rapport
"""

import io
import logging
import uuid

import qrcode
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.assignment import Assignment
from app.models.student import Student
from app.models.trip import Trip, TripStudent
from app.schemas.qr_email import QrEmailSendResult
from app.services.email_service import send_qr_code_email

logger = logging.getLogger(__name__)


def generate_qr_image(token_uid: str) -> bytes:
    """Génère une image PNG du QR code encodant le token_uid donné."""
    qr = qrcode.QRCode(version=1, box_size=10, border=4)
    qr.add_data(token_uid)
    qr.make(fit=True)
    img = qr.make_image(fill_color="black", back_color="white")
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return buf.getvalue()


def _generate_token_uid() -> str:
    """Génère un identifiant unique pour un QR code digital (format : QRD-XXXXXXXX)."""
    return "QRD-" + uuid.uuid4().hex[:8].upper()


def send_qr_emails_for_trip(db: Session, trip_id: uuid.UUID) -> QrEmailSendResult:
    """
    Envoie les QR codes digitaux par email à tous les élèves d'un voyage.

    Règles métier :
    - Élève sans email → comptabilisé dans no_email_count, aucun envoi
    - Élève avec assignation active (NFC, QR physique ou QR digital) → already_sent_count
    - Erreur SMTP individuelle → log + ajout dans errors, pas d'assignation créée
    - L'assignation QR_DIGITAL n'est créée qu'après envoi email réussi

    Lève ValueError si le voyage est introuvable ou archivé.
    """
    # Vérifier que le voyage existe et peut recevoir des envois
    trip = db.execute(select(Trip).where(Trip.id == trip_id)).scalar()
    if not trip:
        raise ValueError("Voyage introuvable.")
    if trip.status == "ARCHIVED":
        raise ValueError("Impossible d'envoyer des QR codes pour un voyage archivé.")

    result = QrEmailSendResult(
        trip_id=trip_id,
        sent_count=0,
        already_sent_count=0,
        no_email_count=0,
        errors=[],
    )

    # Récupérer tous les élèves inscrits au voyage
    participants = db.execute(
        select(Student)
        .join(TripStudent, TripStudent.student_id == Student.id)
        .where(TripStudent.trip_id == trip_id)
    ).scalars().all()

    assignments_to_add = []

    for student in participants:
        # Skip si l'élève n'a pas d'adresse email
        if not student.email:
            result.no_email_count += 1
            continue

        # Skip si l'élève a déjà une assignation active sur ce voyage (quel que soit le type).
        # Raison : idx_assignments_active_student_trip impose l'unicité (student_id, trip_id)
        # WHERE released_at IS NULL. Tenter d'insérer un QR_DIGITAL pour un élève ayant déjà
        # un NFC/QR physique provoquerait une violation de contrainte et un rollback global.
        existing = db.execute(
            select(Assignment).where(
                Assignment.student_id == student.id,
                Assignment.trip_id == trip_id,
                Assignment.released_at.is_(None),
            )
        ).scalar()

        if existing:
            result.already_sent_count += 1
            continue

        # Générer le token unique et l'image QR, puis envoyer l'email
        token_uid = _generate_token_uid()
        try:
            qr_bytes = generate_qr_image(token_uid)
            send_qr_code_email(
                to_email=student.email,
                student_name=f"{student.first_name} {student.last_name}",
                trip_destination=trip.destination,
                trip_date=trip.date,
                qr_image_bytes=qr_bytes,
            )
            # L'assignation n'est ajoutée qu'après succès de l'envoi
            assignments_to_add.append(
                Assignment(
                    token_uid=token_uid,
                    student_id=student.id,
                    trip_id=trip_id,
                    assignment_type="QR_DIGITAL",
                )
            )
            result.sent_count += 1
            logger.info(
                "QR code envoyé à %s (élève %s, voyage %s)",
                student.email, student.id, trip_id,
            )
        except Exception as exc:
            error_msg = f"Erreur envoi email {student.email} : {exc}"
            result.errors.append(error_msg)
            logger.error(error_msg)

    # Persister toutes les nouvelles assignations en une seule transaction
    for assignment in assignments_to_add:
        db.add(assignment)
    db.commit()

    return result
