"""
Schémas Pydantic pour l'envoi des QR codes par email (US 1.6).
"""

import uuid
from typing import List

from pydantic import BaseModel


class QrEmailSendResult(BaseModel):

    trip_id: uuid.UUID
    sent_count: int
    already_sent_count: int
    no_email_count: int
    errors: List[str]
