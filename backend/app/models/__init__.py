# Importe tous les modèles pour enregistrer leurs tables dans Base.metadata
# avant que SQLAlchemy tente de résoudre les clés étrangères inter-modèles.
# Sans cet import, les FK comme assignments.assigned_by → users.id échouent
# avec NoReferencedTableError si user.py n'est pas chargé avant assignment.py.

from app.models.user import User  # noqa: F401  — doit précéder assignment
from app.models.student import Student  # noqa: F401
from app.models.school_class import SchoolClass, ClassStudent, ClassTeacher  # noqa: F401
from app.models.trip import Trip, TripStudent  # noqa: F401
from app.models.assignment import Assignment, Token  # noqa: F401
from app.models.checkpoint import Checkpoint  # noqa: F401
from app.models.attendance import Attendance  # noqa: F401
