"""
Schemas Pydantic pour les alertes temps reel (US 4.3).
"""

import uuid
from datetime import datetime
from typing import Optional

from pydantic import BaseModel


class AlertCreate(BaseModel):
    trip_id: uuid.UUID
    checkpoint_id: Optional[uuid.UUID] = None
    student_id: uuid.UUID
    alert_type: str  # STUDENT_MISSING, CHECKPOINT_DELAYED, SYNC_FAILED
    severity: str = "MEDIUM"  # LOW, MEDIUM, HIGH, CRITICAL
    message: Optional[str] = None


class AlertResponse(BaseModel):
    id: uuid.UUID
    trip_id: uuid.UUID
    checkpoint_id: Optional[uuid.UUID] = None
    student_id: uuid.UUID
    student_name: Optional[str] = None
    trip_destination: Optional[str] = None
    checkpoint_name: Optional[str] = None
    alert_type: str
    severity: str
    message: Optional[str] = None
    status: str
    created_by: Optional[uuid.UUID] = None
    resolved_by: Optional[uuid.UUID] = None
    created_at: Optional[datetime] = None
    resolved_at: Optional[datetime] = None


class AlertUpdate(BaseModel):
    status: str  # IN_PROGRESS, RESOLVED


class AlertStats(BaseModel):
    total: int
    active: int
    in_progress: int
    resolved: int
    critical: int
