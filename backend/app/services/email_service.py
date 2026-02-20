"""
Service d'envoi d'emails SMTP (US 1.6).
Utilisé pour l'envoi des QR codes digitaux aux parents/élèves avant un voyage.
"""

import logging
import smtplib
from datetime import date
from email.mime.image import MIMEImage
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText

from app.config import settings

logger = logging.getLogger(__name__)


def send_qr_code_email(
    to_email: str,
    student_name: str,
    trip_destination: str,
    trip_date: date,
    qr_image_bytes: bytes,
) -> None:
    """
    Envoie un email HTML contenant le QR code digital de l'élève pour un voyage.
    Le QR code est intégré en ligne dans le corps de l'email (Content-ID).
    Lève une exception en cas d'échec SMTP.
    """
    msg = MIMEMultipart("related")
    msg["From"] = settings.SMTP_FROM
    msg["To"] = to_email
    msg["Subject"] = (
        f"SchoolTrack — Votre QR code pour le voyage à {trip_destination} "
        f"le {trip_date.strftime('%d/%m/%Y')}"
    )

    # Corps HTML avec QR code intégré via Content-ID
    html_content = f"""
    <html>
      <body style="font-family: Arial, sans-serif; color: #333; max-width: 600px; margin: auto;">
        <h2 style="color: #1a73e8;">SchoolTrack — QR Code de présence</h2>
        <p>Bonjour,</p>
        <p>
          Voici le QR code de <strong>{student_name}</strong> pour le voyage scolaire à
          <strong>{trip_destination}</strong> prévu le <strong>{trip_date.strftime('%d/%m/%Y')}</strong>.
        </p>
        <p>
          Veuillez présenter ce QR code lors de chaque point de contrôle durant la sortie.
          Il peut être affiché sur un écran ou imprimé.
        </p>
        <div style="text-align: center; margin: 24px 0;">
          <img src="cid:qrcode" alt="QR Code de présence" style="width: 220px; height: 220px;" />
        </div>
        <hr style="border: none; border-top: 1px solid #eee;" />
        <p style="font-size: 12px; color: #888;">
          Ce message est généré automatiquement par SchoolTrack. Ne pas répondre à cet email.
        </p>
      </body>
    </html>
    """

    html_part = MIMEMultipart("alternative")
    html_part.attach(MIMEText(html_content, "html", "utf-8"))
    msg.attach(html_part)

    # QR code en pièce jointe inline (référencé par cid:qrcode dans le HTML)
    qr_attachment = MIMEImage(qr_image_bytes, name="qrcode.png")
    qr_attachment.add_header("Content-ID", "<qrcode>")
    qr_attachment.add_header("Content-Disposition", "inline", filename="qrcode.png")
    msg.attach(qr_attachment)

    # Connexion SMTP et envoi
    with smtplib.SMTP(settings.SMTP_HOST, settings.SMTP_PORT) as server:
        if settings.SMTP_USE_TLS:
            server.starttls()
        if settings.SMTP_USERNAME:
            server.login(settings.SMTP_USERNAME, settings.SMTP_PASSWORD)
        server.send_message(msg)

    logger.info("Email QR code envoyé à %s pour le voyage à %s", to_email, trip_destination)
