"""
Service metier pour les tokens (US 1.4) et l'assignation des bracelets (US 1.5).
"""

import csv
import io
import uuid
import logging
from datetime import datetime
from typing import List, Optional

from sqlalchemy import and_, func, select
from sqlalchemy.orm import Session

from app.models.assignment import Assignment, Token
from app.models.student import Student
from app.models.trip import Trip, TripStudent
from app.schemas.assignment import (
    AssignmentCreate,
    AssignmentReassign,
    AssignmentResponse,
    TokenBatchCreate,
    TokenCreate,
    TokenResponse,
    TokenStatsResponse,
    TripAssignmentStatus,
    TripStudentWithAssignment,
    TripStudentsResponse,
)

logger = logging.getLogger(__name__)

# Categorie physique vs digitale pour la double assignation
PHYSICAL_TYPES = {"NFC_PHYSICAL", "QR_PHYSICAL"}


def _is_physical(assignment_type: str) -> bool:
    return assignment_type in PHYSICAL_TYPES


def assign_token(
    db: Session,
    data: AssignmentCreate,
    assigned_by: Optional[uuid.UUID] = None,
) -> AssignmentResponse:
    """
    Assigne un bracelet à un élève pour un voyage.

    Validations :
    1. L'élève est bien inscrit au voyage (trip_students)
    2. Le token n'est pas déjà activement assigné sur ce voyage
    3. L'élève n'a pas déjà un token actif sur ce voyage
    """
    # 1. Vérifier que l'élève participe au voyage
    is_participant = db.execute(
        select(TripStudent)
        .where(
            TripStudent.trip_id == data.trip_id,
            TripStudent.student_id == data.student_id,
        )
    ).scalar()

    if not is_participant:
        raise ValueError("Cet élève n'est pas inscrit à ce voyage.")

    # 2. Verifier que le token n'est pas deja assigne sur ce voyage
    token_taken = db.execute(
        select(Assignment)
        .where(
            Assignment.token_uid == data.token_uid,
            Assignment.trip_id == data.trip_id,
            Assignment.released_at.is_(None),
        )
    ).scalar()

    if token_taken:
        # Verifier si l'assignation est orpheline (eleve retire du voyage)
        still_enrolled = db.execute(
            select(TripStudent).where(
                TripStudent.student_id == token_taken.student_id,
                TripStudent.trip_id == token_taken.trip_id,
            )
        ).scalar()
        if not still_enrolled:
            # Assignation orpheline → liberer automatiquement
            token_taken.released_at = datetime.now()
            logger.info("Assignation orpheline #%d liberee (eleve retire du voyage)", token_taken.id)
            db.flush()
        else:
            raise ValueError(f"Le bracelet '{data.token_uid}' est deja assigne sur ce voyage.")

    # 3. Verifier que l'eleve n'a pas deja un bracelet de la MEME categorie sur ce voyage
    #    (physique OU digital — permet d'avoir 1 physique + 1 digital simultanément)
    new_is_physical = _is_physical(data.assignment_type)
    student_assignments = db.execute(
        select(Assignment)
        .where(
            Assignment.student_id == data.student_id,
            Assignment.trip_id == data.trip_id,
            Assignment.released_at.is_(None),
        )
    ).scalars().all()

    for existing in student_assignments:
        if _is_physical(existing.assignment_type) == new_is_physical:
            category = "physique" if new_is_physical else "digital"
            raise ValueError(f"Cet eleve a deja un bracelet {category} assigne sur ce voyage.")

    assignment = Assignment(
        token_uid=data.token_uid,
        student_id=data.student_id,
        trip_id=data.trip_id,
        assignment_type=data.assignment_type,
        assigned_by=assigned_by,
    )
    db.add(assignment)

    # Mettre à jour le statut du token physique si présent en BDD
    _update_token_status(db, data.token_uid, "ASSIGNED")

    db.commit()
    db.refresh(assignment)

    logger.info("Bracelet %s assigné à élève %s (voyage %s)", data.token_uid, data.student_id, data.trip_id)
    return AssignmentResponse.model_validate(assignment)


def reassign_token(
    db: Session,
    data: AssignmentReassign,
    assigned_by: Optional[uuid.UUID] = None,
) -> AssignmentResponse:
    """
    Réassigne un bracelet : libère toutes les assignations actives liées
    à ce token OU à cet élève sur ce voyage, puis crée une nouvelle assignation.
    """
    # Libérer l'assignation active du token sur ce voyage (si elle existe)
    old_token = db.execute(
        select(Assignment)
        .where(
            Assignment.token_uid == data.token_uid,
            Assignment.trip_id == data.trip_id,
            Assignment.released_at.is_(None),
        )
    ).scalar()

    if old_token:
        old_token.released_at = datetime.now()
        # Remettre l'ancien token en AVAILABLE
        _update_token_status(db, old_token.token_uid, "AVAILABLE")

    # Liberer l'assignation active de l'eleve de MEME CATEGORIE sur ce voyage
    new_is_physical = _is_physical(data.assignment_type)
    old_student_assignments = db.execute(
        select(Assignment)
        .where(
            Assignment.student_id == data.student_id,
            Assignment.trip_id == data.trip_id,
            Assignment.released_at.is_(None),
        )
    ).scalars().all()

    for old_assign in old_student_assignments:
        if old_assign is not old_token and _is_physical(old_assign.assignment_type) == new_is_physical:
            old_assign.released_at = datetime.now()
            _update_token_status(db, old_assign.token_uid, "AVAILABLE")

    # Forcer l'envoi des UPDATEs à PostgreSQL AVANT l'INSERT.
    # Sans flush(), SQLAlchemy peut envoyer l'INSERT avant les UPDATEs,
    # ce qui viole le partial unique index (student_id, trip_id) WHERE released_at IS NULL
    # car l'ancienne ligne a encore released_at=NULL au moment de la vérification.
    db.flush()

    # Créer la nouvelle assignation
    assignment = Assignment(
        token_uid=data.token_uid,
        student_id=data.student_id,
        trip_id=data.trip_id,
        assignment_type=data.assignment_type,
        assigned_by=assigned_by,
    )
    db.add(assignment)
    _update_token_status(db, data.token_uid, "ASSIGNED")
    db.commit()
    db.refresh(assignment)

    logger.info(
        "Réassignation bracelet %s → élève %s (voyage %s) — justification : %s",
        data.token_uid, data.student_id, data.trip_id, data.justification
    )
    return AssignmentResponse.model_validate(assignment)


def get_trip_assignment_status(db: Session, trip_id: uuid.UUID) -> TripAssignmentStatus:
    """
    Retourne le statut complet des assignations pour un voyage :
    total élèves, élèves assignés, élèves non assignés, liste des assignations.
    """
    total_students = db.execute(
        select(func.count()).select_from(TripStudent).where(TripStudent.trip_id == trip_id)
    ).scalar() or 0

    assignments = db.execute(
        select(Assignment)
        .where(
            Assignment.trip_id == trip_id,
            Assignment.released_at.is_(None),
        )
    ).scalars().all()

    # Compter les eleves distincts avec au moins une assignation
    assigned_students = len({a.student_id for a in assignments})

    return TripAssignmentStatus(
        trip_id=trip_id,
        total_students=total_students,
        assigned_students=assigned_students,
        unassigned_students=total_students - assigned_students,
        assignments=[AssignmentResponse.model_validate(a) for a in assignments],
    )


def export_assignments_csv(db: Session, trip_id: uuid.UUID) -> str:
    """
    Génère un CSV des assignations actives d'un voyage.
    Retourne le contenu CSV sous forme de string (UTF-8 BOM pour Excel).
    """
    assignments = db.execute(
        select(Assignment)
        .where(
            Assignment.trip_id == trip_id,
            Assignment.released_at.is_(None),
        )
        .order_by(Assignment.assigned_at)
    ).scalars().all()

    output = io.StringIO()
    writer = csv.writer(output, delimiter=";")
    writer.writerow(["token_uid", "student_id", "assignment_type", "assigned_at"])

    for a in assignments:
        writer.writerow([
            a.token_uid,
            str(a.student_id),
            a.assignment_type,
            a.assigned_at.strftime("%Y-%m-%d %H:%M:%S") if a.assigned_at else "",
        ])

    return "\ufeff" + output.getvalue()  # BOM pour compatibilité Excel


def get_trip_students_with_assignments(
    db: Session, trip_id: uuid.UUID
) -> TripStudentsResponse:
    """
    Retourne la liste des eleves inscrits a un voyage avec leurs assignations
    (primaire physique + secondaire digitale).
    Utilise par le dashboard web pour l'ecran d'assignation (US 1.5).
    """
    # 1. Tous les eleves du voyage
    students_rows = db.execute(
        select(Student)
        .join(TripStudent, TripStudent.student_id == Student.id)
        .where(TripStudent.trip_id == trip_id)
    ).scalars().all()

    # 2. Toutes les assignations actives du voyage
    assignments = db.execute(
        select(Assignment)
        .where(
            Assignment.trip_id == trip_id,
            Assignment.released_at.is_(None),
        )
    ).scalars().all()

    # 3. Map student_id → {primary: Assignment, secondary: Assignment}
    assignment_map: dict[uuid.UUID, dict[str, Assignment]] = {}
    for a in assignments:
        key = "primary" if _is_physical(a.assignment_type) else "secondary"
        assignment_map.setdefault(a.student_id, {})[key] = a

    # 4. Tri alphabetique en Python (colonnes chiffrees, US 6.3)
    students_rows = sorted(
        students_rows,
        key=lambda s: ((s.last_name or "").lower(), (s.first_name or "").lower()),
    )

    # 5. Construire la reponse avec les 2 sets de champs
    students = []
    primary_count = 0
    digital_count = 0
    for student in students_rows:
        student_assigns = assignment_map.get(student.id, {})
        primary = student_assigns.get("primary")
        secondary = student_assigns.get("secondary")

        if primary:
            primary_count += 1
        if secondary:
            digital_count += 1

        students.append(
            TripStudentWithAssignment(
                id=student.id,
                first_name=student.first_name,
                last_name=student.last_name,
                email=student.email,
                assignment_id=primary.id if primary else None,
                token_uid=primary.token_uid if primary else None,
                assignment_type=primary.assignment_type if primary else None,
                assigned_at=primary.assigned_at if primary else None,
                secondary_assignment_id=secondary.id if secondary else None,
                secondary_token_uid=secondary.token_uid if secondary else None,
                secondary_assignment_type=secondary.assignment_type if secondary else None,
                secondary_assigned_at=secondary.assigned_at if secondary else None,
            )
        )

    logger.info(
        "Statut assignations voyage %s : %d/%d physiques, %d digitaux",
        trip_id, primary_count, len(students), digital_count,
    )
    return TripStudentsResponse(
        trip_id=trip_id,
        total=len(students),
        assigned=primary_count,
        unassigned=len(students) - primary_count,
        assigned_digital=digital_count,
        students=students,
    )


def release_trip_tokens(db: Session, trip_id: uuid.UUID) -> int:
    """
    Libère toutes les assignations actives d'un voyage en settant released_at = NOW().

    Appelé automatiquement quand un voyage passe à COMPLETED ou ARCHIVED,
    ou manuellement via POST /api/v1/trips/{id}/release-tokens.

    Retourne le nombre d'assignations libérées (0 si aucune active).
    """
    assignments = db.execute(
        select(Assignment)
        .where(
            Assignment.trip_id == trip_id,
            Assignment.released_at.is_(None),
        )
    ).scalars().all()

    count = len(assignments)
    if count == 0:
        return 0

    now = datetime.now()
    for a in assignments:
        a.released_at = now
        # Remettre le token physique en AVAILABLE
        _update_token_status(db, a.token_uid, "AVAILABLE")

    db.commit()
    logger.info("Voyage %s : %d bracelet(s) libéré(s)", trip_id, count)
    return count


def release_assignment(db: Session, assignment_id: int) -> dict:
    """
    Libere une assignation individuelle en settant released_at = NOW().
    Remet le token physique en AVAILABLE.
    Retourne les details de l'assignation liberee (student, token, trip).
    Leve ValueError si l'assignation est introuvable ou deja liberee.
    """
    assignment = db.execute(
        select(Assignment).where(Assignment.id == assignment_id)
    ).scalar()

    if assignment is None:
        raise ValueError("Assignation introuvable.")

    if assignment.released_at is not None:
        raise ValueError("Cette assignation est deja liberee.")

    # Recuperer les infos pour la reponse avant de modifier
    from app.models.student import Student
    from app.models.trip import Trip
    student = db.get(Student, assignment.student_id)
    trip = db.get(Trip, assignment.trip_id)

    # Liberer l'assignation
    assignment.released_at = datetime.now()

    # Remettre le token physique en AVAILABLE
    _update_token_status(db, assignment.token_uid, "AVAILABLE")

    db.commit()

    student_name = f"{student.first_name} {student.last_name}" if student else "Inconnu"
    trip_name = trip.destination if trip else "Inconnu"

    logger.info(
        "Assignation %d liberee : token %s, eleve %s, voyage %s",
        assignment_id, assignment.token_uid, student_name, trip_name,
    )

    return {
        "assignment_id": assignment_id,
        "token_uid": assignment.token_uid,
        "student_name": student_name,
        "trip_name": trip_name,
    }


def _update_token_status(db: Session, token_uid: str, status: str) -> None:
    """Met à jour le statut d'un token physique s'il est enregistré en BDD."""
    token = db.execute(
        select(Token).where(Token.token_uid == token_uid)
    ).scalar()

    if token:
        token.status = status
        token.last_assigned_at = datetime.now()


# ----------------------------------------------------------------
# US 1.4 — Initialisation du stock de bracelets
# ----------------------------------------------------------------


def init_token(db: Session, data: TokenCreate, school_id: uuid.UUID) -> TokenResponse:
    """
    Enregistre un token unique dans le stock.
    Verifie que le token_uid n'existe pas deja.
    """
    existing = db.execute(
        select(Token).where(Token.token_uid == data.token_uid)
    ).scalar()

    if existing:
        raise ValueError(f"Le token '{data.token_uid}' existe deja dans le stock.")

    token = Token(
        school_id=school_id,
        token_uid=data.token_uid,
        token_type=data.token_type,
        hardware_uid=data.hardware_uid,
        status="AVAILABLE",
    )
    db.add(token)
    db.commit()
    db.refresh(token)

    logger.info("Token %s (%s) enregistre dans le stock", data.token_uid, data.token_type)
    return TokenResponse.model_validate(token)


def init_tokens_batch(db: Session, data: TokenBatchCreate, school_id: uuid.UUID) -> List[TokenResponse]:
    """
    Enregistre un lot de tokens dans le stock.
    Verifie les doublons et retourne la liste des tokens crees.
    """
    # Verifier les doublons internes au batch
    uids = [t.token_uid for t in data.tokens]
    if len(uids) != len(set(uids)):
        raise ValueError("Le lot contient des token_uid en double.")

    # Verifier les doublons avec la BDD
    existing = db.execute(
        select(Token.token_uid).where(Token.token_uid.in_(uids))
    ).scalars().all()

    if existing:
        raise ValueError(f"Token(s) deja existant(s) : {', '.join(existing)}")

    tokens = []
    for item in data.tokens:
        token = Token(
            school_id=school_id,
            token_uid=item.token_uid,
            token_type=item.token_type,
            hardware_uid=item.hardware_uid,
            status="AVAILABLE",
        )
        tokens.append(token)

    db.add_all(tokens)
    db.commit()

    # Refresh pour obtenir les id et created_at
    for t in tokens:
        db.refresh(t)

    logger.info("%d token(s) enregistre(s) dans le stock", len(tokens))
    return [TokenResponse.model_validate(t) for t in tokens]


def list_tokens(
    db: Session,
    school_id: uuid.UUID,
    status: Optional[str] = None,
    token_type: Optional[str] = None,
) -> List[TokenResponse]:
    """
    Liste les tokens du stock pour une école donnée, avec filtres optionnels.
    Enrichit les tokens ASSIGNED avec le nom de l'eleve et du voyage.
    """
    query = select(Token).where(Token.school_id == school_id).order_by(Token.token_uid)

    if status:
        query = query.where(Token.status == status)
    if token_type:
        query = query.where(Token.token_type == token_type)

    tokens = db.execute(query).scalars().all()

    # Charger les assignations actives en une seule requete
    assigned_uids = [t.token_uid for t in tokens if t.status == "ASSIGNED"]
    assignment_map: dict[str, tuple[str, str]] = {}
    if assigned_uids:
        rows = db.execute(
            select(Assignment.token_uid, Student.first_name, Student.last_name, Trip.destination)
            .join(Student, Student.id == Assignment.student_id)
            .join(Trip, Trip.id == Assignment.trip_id)
            .where(
                Assignment.token_uid.in_(assigned_uids),
                Assignment.released_at.is_(None),
            )
        ).all()
        for token_uid, first_name, last_name, destination in rows:
            assignment_map[token_uid] = (f"{first_name} {last_name}", destination)

    results = []
    for t in tokens:
        resp = TokenResponse.model_validate(t)
        if t.token_uid in assignment_map:
            resp.assigned_to = assignment_map[t.token_uid][0]
            resp.assigned_trip = assignment_map[t.token_uid][1]
        results.append(resp)

    return results


def get_token_stats(db: Session, school_id: uuid.UUID) -> TokenStatsResponse:
    """
    Retourne les statistiques du stock de tokens pour une école donnée.
    """
    total = db.execute(
        select(func.count()).select_from(Token).where(Token.school_id == school_id)
    ).scalar() or 0
    available = db.execute(
        select(func.count()).select_from(Token).where(Token.school_id == school_id, Token.status == "AVAILABLE")
    ).scalar() or 0
    assigned = db.execute(
        select(func.count()).select_from(Token).where(Token.school_id == school_id, Token.status == "ASSIGNED")
    ).scalar() or 0
    damaged = db.execute(
        select(func.count()).select_from(Token).where(Token.school_id == school_id, Token.status == "DAMAGED")
    ).scalar() or 0
    lost = db.execute(
        select(func.count()).select_from(Token).where(Token.school_id == school_id, Token.status == "LOST")
    ).scalar() or 0

    return TokenStatsResponse(
        total=total,
        available=available,
        assigned=assigned,
        damaged=damaged,
        lost=lost,
    )


def get_next_sequence(db: Session, prefix: str, school_id: uuid.UUID) -> dict:
    """
    Retourne le prochain numero de sequence disponible pour un prefixe donne,
    dans le stock de l'école donnée.
    Scanne les token_uid existants au format PREFIX-NNN et retourne max + 1.
    """
    import re
    pattern = f"{prefix}-"
    rows = db.execute(
        select(Token.token_uid).where(Token.school_id == school_id, Token.token_uid.like(f"{pattern}%"))
    ).scalars().all()

    max_seq = 0
    for uid in rows:
        # Extraire la partie numerique apres le prefixe
        suffix = uid[len(pattern):]
        match = re.match(r"^(\d+)$", suffix)
        if match:
            max_seq = max(max_seq, int(match.group(1)))

    return {"prefix": prefix, "next_sequence": max_seq + 1}


def get_token_assignment_info(db: Session, token_id: int, school_id: uuid.UUID) -> Optional[dict]:
    """
    Retourne les infos de l'assignation active d'un token (eleve + voyage).
    Retourne None si le token n'est pas assigne ou n'appartient pas a l'ecole.
    """
    token = db.execute(
        select(Token).where(Token.id == token_id, Token.school_id == school_id)
    ).scalar()
    if token is None or token.status != "ASSIGNED":
        return None

    assignment = db.execute(
        select(Assignment)
        .where(
            Assignment.token_uid == token.token_uid,
            Assignment.released_at.is_(None),
        )
    ).scalar()

    if assignment is None:
        return None

    student = db.get(Student, assignment.student_id)
    trip = db.get(Trip, assignment.trip_id)

    return {
        "assignment_id": assignment.id,
        "student_name": f"{student.first_name} {student.last_name}" if student else "Inconnu",
        "student_id": str(assignment.student_id),
        "trip_name": trip.destination if trip else "Inconnu",
        "trip_id": str(assignment.trip_id),
        "assigned_at": assignment.assigned_at.isoformat() if assignment.assigned_at else None,
    }


def delete_token(db: Session, token_id: int, school_id: uuid.UUID) -> None:
    """
    Supprime un token du stock par son id.
    Interdit si le token est actuellement ASSIGNED ou n'appartient pas a l'ecole.
    """
    token = db.execute(
        select(Token).where(Token.id == token_id, Token.school_id == school_id)
    ).scalar()

    if not token:
        raise ValueError(f"Token avec id={token_id} introuvable.")

    if token.status == "ASSIGNED":
        raise ValueError("Impossible de supprimer un token actuellement assigne.")

    db.delete(token)
    db.commit()

    logger.info("Token %s (id=%d) supprime du stock", token.token_uid, token_id)


def update_token_status_by_id(db: Session, token_id: int, status: str, school_id: uuid.UUID) -> TokenResponse:
    """
    Met a jour le statut d'un token par son id.
    Si le token etait ASSIGNED et passe a un autre statut,
    l'assignment actif est automatiquement libere.
    Leve ValueError si le token n'appartient pas a l'ecole.
    """
    token = db.execute(
        select(Token).where(Token.id == token_id, Token.school_id == school_id)
    ).scalar()

    if not token:
        raise ValueError(f"Token avec id={token_id} introuvable.")

    # Si le token etait assigne, liberer l'assignment actif
    if token.status == "ASSIGNED" and status != "ASSIGNED":
        active_assignment = db.execute(
            select(Assignment).where(
                Assignment.token_uid == token.token_uid,
                Assignment.released_at.is_(None),
            )
        ).scalar()
        if active_assignment:
            active_assignment.released_at = datetime.utcnow()
            logger.info(
                "Assignment #%d libere automatiquement (token %s → %s)",
                active_assignment.id, token.token_uid, status,
            )

    token.status = status
    db.commit()
    db.refresh(token)

    logger.info("Token %s : statut mis a jour → %s", token.token_uid, status)
    return TokenResponse.model_validate(token)
