"""
Service métier pour les voyages (US 1.2, US 4.1).
Gère la création, la lecture, la modification, l'archivage et l'export CSV des voyages.
"""

import csv
import io
import uuid
import logging
from datetime import datetime
from typing import Optional

from sqlalchemy import and_, delete, func, select
from sqlalchemy.orm import Session

from app.models.attendance import Attendance
from app.models.checkpoint import Checkpoint
from app.models.school_class import ClassStudent, SchoolClass
from app.models.student import Student
from app.models.trip import Trip, TripClass, TripStudent
from app.schemas.trip import ClassSummary, TripCreate, TripResponse, TripUpdate
from app.services import assignment_service

logger = logging.getLogger(__name__)


def create_trip(db: Session, data: TripCreate, created_by: Optional[uuid.UUID] = None) -> TripResponse:
    """
    Crée un voyage et associe automatiquement les élèves des classes sélectionnées.

    Étapes :
    1. Créer l'entrée dans trips
    2. Récupérer les élèves des classes via class_students
    3. Insérer en bulk dans trip_students (dédupliqué)
    4. TODO US 1.6 : notifier les enseignants responsables par email
    """
    trip = Trip(
        destination=data.destination,
        date=data.date,
        description=data.description,
        created_by=created_by,
        status="PLANNED",
    )
    db.add(trip)
    db.flush()  # Obtenir l'ID avant le commit

    # Sauvegarder les classes sélectionnées explicitement
    for cid in data.class_ids:
        db.add(TripClass(trip_id=trip.id, class_id=cid))

    # Récupérer les élèves des classes sélectionnées (dédupliqué)
    student_ids = db.execute(
        select(ClassStudent.student_id)
        .where(ClassStudent.class_id.in_(data.class_ids))
        .distinct()
    ).scalars().all()

    if student_ids:
        db.bulk_insert_mappings(TripStudent, [
            {"trip_id": trip.id, "student_id": sid}
            for sid in student_ids
        ])

    db.commit()
    db.refresh(trip)

    # TODO US 1.6 : envoyer une notification email aux enseignants responsables des classes
    logger.info(
        "Voyage créé : %s (%s) — %d élèves associés",
        trip.destination, trip.id, len(student_ids)
    )

    return _to_response(db, trip)


def get_trips(db: Session) -> list[TripResponse]:
    """Retourne tous les voyages non supprimés, du plus proche au plus loin."""
    trips = db.execute(
        select(Trip)
        .where(Trip.status != "ARCHIVED")
        .order_by(Trip.date.asc())
    ).scalars().all()

    return [_to_response(db, t) for t in trips]


def get_trip(db: Session, trip_id: uuid.UUID) -> Optional[TripResponse]:
    """Retourne un voyage par son ID, ou None s'il n'existe pas."""
    trip = db.get(Trip, trip_id)
    if trip is None:
        return None
    return _to_response(db, trip)


def update_trip(db: Session, trip_id: uuid.UUID, data: TripUpdate) -> Optional[TripResponse]:
    """
    Met à jour les champs modifiables d'un voyage.
    Si class_ids est fourni, les élèves du voyage sont recalculés depuis les nouvelles classes
    (suppression des anciens + insertion des nouveaux, dédupliqués).
    Si le statut passe à COMPLETED ou ARCHIVED, libère automatiquement
    toutes les assignations de bracelets actives du voyage.
    """
    trip = db.get(Trip, trip_id)
    if trip is None:
        return None

    # Mise à jour des champs scalaires (hors class_ids)
    update_data = data.model_dump(exclude_unset=True, exclude={"class_ids"})
    new_status = update_data.get("status")

    for field, value in update_data.items():
        setattr(trip, field, value)

    # Recalcul des élèves et classes si de nouvelles classes sont fournies
    if data.class_ids is not None:
        # Supprimer les anciennes associations classes et élèves
        db.execute(
            delete(TripClass).where(TripClass.trip_id == trip.id)
        )
        db.execute(
            delete(TripStudent).where(TripStudent.trip_id == trip.id)
        )

        # Sauvegarder les nouvelles classes sélectionnées
        for cid in data.class_ids:
            db.add(TripClass(trip_id=trip.id, class_id=cid))

        # Récupérer les élèves des nouvelles classes (dédupliqué)
        student_ids = db.execute(
            select(ClassStudent.student_id)
            .where(ClassStudent.class_id.in_(data.class_ids))
            .distinct()
        ).scalars().all()

        if student_ids:
            db.bulk_insert_mappings(TripStudent, [
                {"trip_id": trip.id, "student_id": sid}
                for sid in student_ids
            ])

    db.commit()
    db.refresh(trip)

    # Libération automatique des bracelets quand le voyage est terminé ou archivé
    if new_status in ("COMPLETED", "ARCHIVED"):
        assignment_service.release_trip_tokens(db, trip_id)

    return _to_response(db, trip)


def archive_trip(db: Session, trip_id: uuid.UUID) -> bool:
    """
    Archive un voyage (suppression logique) et libère les bracelets actifs.
    Retourne True si archivé, False si non trouvé.
    """
    trip = db.get(Trip, trip_id)
    if trip is None:
        return False

    trip.status = "ARCHIVED"
    db.commit()

    # Libération automatique des bracelets à l'archivage
    assignment_service.release_trip_tokens(db, trip_id)
    return True


def _to_response(db: Session, trip: Trip) -> TripResponse:
    """Construit le schéma de réponse avec le total d'élèves et les classes représentées."""
    total = db.execute(
        select(func.count())
        .select_from(TripStudent)
        .where(TripStudent.trip_id == trip.id)
    ).scalar() or 0

    # Classes explicitement sélectionnées pour le voyage (trip_classes)
    class_rows = db.execute(
        select(SchoolClass.name, func.count(TripStudent.student_id).label("cnt"))
        .join(TripClass, TripClass.class_id == SchoolClass.id)
        .outerjoin(ClassStudent, ClassStudent.class_id == SchoolClass.id)
        .outerjoin(
            TripStudent,
            and_(
                TripStudent.student_id == ClassStudent.student_id,
                TripStudent.trip_id == trip.id,
            ),
        )
        .where(TripClass.trip_id == trip.id)
        .group_by(SchoolClass.id, SchoolClass.name)
        .order_by(SchoolClass.name)
    ).all()

    classes = [ClassSummary(name=row.name, student_count=row.cnt) for row in class_rows]

    return TripResponse(
        id=trip.id,
        destination=trip.destination,
        date=trip.date,
        description=trip.description,
        status=trip.status,
        total_students=total,
        classes=classes,
        created_at=trip.created_at,
        updated_at=trip.updated_at,
    )


# ---------------------------------------------------------------------------
# US 4.1 — Export CSV presences
# ---------------------------------------------------------------------------


def export_attendance_csv(db: Session, trip_id: uuid.UUID) -> tuple[str, Trip]:
    """
    Genere le contenu CSV des presences pour un voyage.
    Retourne (csv_string, trip_object) pour que le router construise le filename.
    Leve ValueError si le voyage est introuvable.
    """
    trip = db.get(Trip, trip_id)
    if trip is None:
        raise ValueError("Voyage introuvable.")

    # Total eleves inscrits au voyage
    total_students = db.execute(
        select(func.count())
        .select_from(TripStudent)
        .where(TripStudent.trip_id == trip.id)
    ).scalar() or 0

    # Dict {student_id: class_name} via class_students + school_classes
    class_map: dict[uuid.UUID, str] = {}
    class_rows = db.execute(
        select(ClassStudent.student_id, SchoolClass.name)
        .join(SchoolClass, SchoolClass.id == ClassStudent.class_id)
        .join(
            TripStudent,
            and_(
                TripStudent.student_id == ClassStudent.student_id,
                TripStudent.trip_id == trip.id,
            ),
        )
    ).all()
    for row in class_rows:
        class_map[row[0]] = row[1]

    # Presences avec student + checkpoint
    attendances = db.execute(
        select(Attendance, Student, Checkpoint)
        .join(Student, Student.id == Attendance.student_id)
        .join(Checkpoint, Checkpoint.id == Attendance.checkpoint_id)
        .where(Attendance.trip_id == trip.id)
    ).all()

    # Tri en Python (colonnes chiffrees)
    attendances_sorted = sorted(
        attendances,
        key=lambda row: (
            (row[1].last_name or "").lower(),
            (row[1].first_name or "").lower(),
            row[2].sequence_order or 0,
        ),
    )

    # Taux de presence par checkpoint
    checkpoint_names: dict[uuid.UUID, str] = {}
    checkpoint_counts: dict[uuid.UUID, set] = {}
    for att, student, cp in attendances_sorted:
        checkpoint_names[cp.id] = cp.name
        if cp.id not in checkpoint_counts:
            checkpoint_counts[cp.id] = set()
        checkpoint_counts[cp.id].add(att.student_id)

    # Construire le CSV
    output = io.StringIO()
    # BOM UTF-8 pour Excel
    output.write("\ufeff")

    # Metadonnees en commentaires
    output.write(f"# Voyage : {trip.destination}\n")
    output.write(f"# Date : {trip.date.strftime('%d/%m/%Y')}\n")
    output.write(f"# Export : {datetime.now().strftime('%d/%m/%Y %H:%M')}\n")
    output.write(f"# Total eleves : {total_students}\n")
    output.write("#\n")
    output.write("# Taux de presence par checkpoint :\n")

    # Ordonner les checkpoints par sequence_order
    ordered_cps = db.execute(
        select(Checkpoint)
        .where(Checkpoint.trip_id == trip.id)
        .order_by(Checkpoint.sequence_order)
    ).scalars().all()

    for cp in ordered_cps:
        count = len(checkpoint_counts.get(cp.id, set()))
        rate = (count / total_students * 100) if total_students > 0 else 0
        output.write(f"# {cp.name} : {rate:.0f}%\n")

    output.write("#\n")

    # En-tete CSV
    writer = csv.writer(output, delimiter=";")
    writer.writerow([
        "Nom", "Prenom", "Classe", "Checkpoint",
        "Heure de passage", "Mode de scan", "Justification",
    ])

    # Lignes de donnees
    for att, student, cp in attendances_sorted:
        if student.is_deleted:
            last_name = "[Supprime]"
            first_name = "[Supprime]"
        else:
            last_name = student.last_name or ""
            first_name = student.first_name or ""

        writer.writerow([
            last_name,
            first_name,
            class_map.get(student.id, ""),
            cp.name,
            att.scanned_at.strftime("%H:%M:%S") if att.scanned_at else "",
            att.scan_method or "",
            att.justification or "",
        ])

    return (output.getvalue(), trip)


def _generate_export_filename(destination: str, trip_date) -> str:
    """Genere un nom de fichier securise pour l'export CSV."""
    safe = destination.replace(" ", "_").replace("/", "-")
    now = datetime.now()
    return f"voyage_{safe}_{trip_date.strftime('%Y-%m-%d')}_{now.strftime('%H-%M')}"
