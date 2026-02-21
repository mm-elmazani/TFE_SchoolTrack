# Import de tous les modèles pour que SQLAlchemy enregistre leurs métadonnées.
# Sans ces imports, les foreign keys vers des tables non chargées lèvent NoReferencedTableError.
from app.models.user import User  # noqa: F401
from app.models.student import Student  # noqa: F401
from app.models.trip import Trip, TripStudent  # noqa: F401
from app.models.school_class import SchoolClass, ClassStudent, ClassTeacher  # noqa: F401
from app.models.assignment import Token, Assignment  # noqa: F401
from app.models.checkpoint import Checkpoint  # noqa: F401
from app.models.attendance import Attendance  # noqa: F401
