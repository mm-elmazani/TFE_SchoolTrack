"""
Schemas Pydantic pour les logs d'audit.
"""

import uuid
from datetime import datetime
from typing import Any, Optional

from pydantic import BaseModel


class AuditLogResponse(BaseModel):

    id: int
    user_id: Optional[uuid.UUID] = None
    user_email: Optional[str] = None
    action: str
    resource_type: Optional[str] = None
    resource_id: Optional[uuid.UUID] = None
    ip_address: Optional[str] = None
    user_agent: Optional[str] = None
    details: Optional[dict[str, Any]] = None
    performed_at: datetime


class AuditLogPage(BaseModel):

    items: list[AuditLogResponse]
    total: int
    page: int
    page_size: int
    total_pages: int
