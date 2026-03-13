"""
Schemas Pydantic pour le dashboard de supervision (US 4.2).
"""

import uuid
from datetime import date, datetime
from typing import Optional

from pydantic import BaseModel


class CheckpointSummary(BaseModel):
    id: uuid.UUID
    name: str
    sequence_order: int
    status: str
    total_expected: int
    total_present: int
    attendance_rate: float
    created_at: Optional[datetime] = None
    closed_at: Optional[datetime] = None


class DashboardTripSummary(BaseModel):
    id: uuid.UUID
    destination: str
    date: date
    status: str
    total_students: int
    total_present: int
    attendance_rate: float
    total_checkpoints: int
    closed_checkpoints: int
    last_checkpoint: Optional[CheckpointSummary] = None
    checkpoints: list[CheckpointSummary] = []


class ScanMethodStats(BaseModel):
    nfc: int = 0
    qr_physical: int = 0
    qr_digital: int = 0
    manual: int = 0
    total: int = 0


class DashboardOverview(BaseModel):
    total_trips: int
    active_trips: int
    planned_trips: int
    completed_trips: int
    total_students: int
    total_attendances: int
    global_attendance_rate: float
    scan_method_stats: ScanMethodStats
    trips: list[DashboardTripSummary] = []
    generated_at: datetime
