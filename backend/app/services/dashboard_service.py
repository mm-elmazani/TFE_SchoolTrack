"""
Service metier pour le dashboard de supervision (US 4.2).
Agrege les statistiques de voyages, presences, checkpoints et modes de scan.
"""

import uuid
from datetime import datetime
from typing import Optional

from sqlalchemy import and_, distinct, func, select
from sqlalchemy.orm import Session

from app.models.attendance import Attendance
from app.models.checkpoint import Checkpoint
from app.models.trip import Trip, TripStudent
from app.schemas.dashboard import (
    CheckpointSummary,
    DashboardOverview,
    DashboardTripSummary,
    ScanMethodStats,
)


def get_dashboard_overview(
    db: Session, status_filter: Optional[str] = None
) -> DashboardOverview:
    """
    Construit la vue d'ensemble du dashboard pour la direction.
    Requetes par lots (pas de N+1).
    """

    # 1. Trips (hors archives sauf si filtre explicite)
    trip_query = select(Trip)
    if status_filter and status_filter != "ALL":
        trip_query = trip_query.where(Trip.status == status_filter)
    else:
        trip_query = trip_query.where(Trip.status != "ARCHIVED")
    trip_query = trip_query.order_by(Trip.date.desc())

    trips = db.execute(trip_query).scalars().all()
    trip_ids = [t.id for t in trips]

    if not trip_ids:
        return DashboardOverview(
            total_trips=0,
            active_trips=0,
            planned_trips=0,
            completed_trips=0,
            total_students=0,
            total_attendances=0,
            global_attendance_rate=0.0,
            scan_method_stats=ScanMethodStats(),
            trips=[],
            generated_at=datetime.now(),
        )

    # 2. Comptage eleves par voyage (batch)
    student_counts_rows = db.execute(
        select(TripStudent.trip_id, func.count(TripStudent.student_id))
        .where(TripStudent.trip_id.in_(trip_ids))
        .group_by(TripStudent.trip_id)
    ).all()
    student_counts: dict[uuid.UUID, int] = {row[0]: row[1] for row in student_counts_rows}

    # 3. Eleves distincts presents par voyage (batch)
    present_counts_rows = db.execute(
        select(Attendance.trip_id, func.count(distinct(Attendance.student_id)))
        .where(Attendance.trip_id.in_(trip_ids))
        .group_by(Attendance.trip_id)
    ).all()
    present_counts: dict[uuid.UUID, int] = {row[0]: row[1] for row in present_counts_rows}

    # 4. Checkpoints par voyage avec nombre de presents (batch)
    cp_query = (
        select(
            Checkpoint,
            func.count(distinct(Attendance.student_id)).label("present_count"),
        )
        .outerjoin(Attendance, Attendance.checkpoint_id == Checkpoint.id)
        .where(Checkpoint.trip_id.in_(trip_ids))
        .group_by(Checkpoint.id)
        .order_by(Checkpoint.trip_id, Checkpoint.sequence_order)
    )
    cp_rows = db.execute(cp_query).all()

    # Grouper checkpoints par trip_id
    checkpoints_by_trip: dict[uuid.UUID, list[tuple]] = {}
    for cp, present_count in cp_rows:
        checkpoints_by_trip.setdefault(cp.trip_id, []).append((cp, present_count))

    # 5. Stats modes de scan (batch)
    scan_rows = db.execute(
        select(Attendance.scan_method, func.count())
        .where(Attendance.trip_id.in_(trip_ids))
        .group_by(Attendance.scan_method)
    ).all()

    scan_stats = ScanMethodStats()
    for method, count in scan_rows:
        if method == "NFC":
            scan_stats.nfc = count
        elif method == "QR_PHYSICAL":
            scan_stats.qr_physical = count
        elif method == "QR_DIGITAL":
            scan_stats.qr_digital = count
        elif method == "MANUAL":
            scan_stats.manual = count
    scan_stats.total = scan_stats.nfc + scan_stats.qr_physical + scan_stats.qr_digital + scan_stats.manual

    # 6. Assembler les reponses par voyage
    trip_summaries: list[DashboardTripSummary] = []
    total_students_global = 0
    total_present_global = 0
    total_attendances = sum(count for _, count in scan_rows)

    status_counts = {"ACTIVE": 0, "PLANNED": 0, "COMPLETED": 0}

    for trip in trips:
        ts = student_counts.get(trip.id, 0)
        tp = present_counts.get(trip.id, 0)
        total_students_global += ts
        total_present_global += tp

        if trip.status in status_counts:
            status_counts[trip.status] += 1

        # Checkpoints de ce voyage
        cp_list = checkpoints_by_trip.get(trip.id, [])
        cp_summaries = []
        closed_cps = 0
        last_cp = None

        for cp, cp_present in cp_list:
            rate = (cp_present / ts * 100) if ts > 0 else 0.0
            summary = CheckpointSummary(
                id=cp.id,
                name=cp.name,
                sequence_order=cp.sequence_order,
                status=cp.status,
                total_expected=ts,
                total_present=cp_present,
                attendance_rate=round(rate, 1),
                created_at=cp.created_at,
                closed_at=cp.closed_at,
            )
            cp_summaries.append(summary)
            if cp.status == "CLOSED":
                closed_cps += 1
                last_cp = summary

        att_rate = (tp / ts * 100) if ts > 0 else 0.0

        trip_summaries.append(DashboardTripSummary(
            id=trip.id,
            destination=trip.destination,
            date=trip.date,
            status=trip.status,
            total_students=ts,
            total_present=tp,
            attendance_rate=round(att_rate, 1),
            total_checkpoints=len(cp_summaries),
            closed_checkpoints=closed_cps,
            last_checkpoint=last_cp,
            checkpoints=cp_summaries,
        ))

    global_rate = (total_present_global / total_students_global * 100) if total_students_global > 0 else 0.0

    return DashboardOverview(
        total_trips=len(trips),
        active_trips=status_counts["ACTIVE"],
        planned_trips=status_counts["PLANNED"],
        completed_trips=status_counts["COMPLETED"],
        total_students=total_students_global,
        total_attendances=total_attendances,
        global_attendance_rate=round(global_rate, 1),
        scan_method_stats=scan_stats,
        trips=trip_summaries,
        generated_at=datetime.now(),
    )
