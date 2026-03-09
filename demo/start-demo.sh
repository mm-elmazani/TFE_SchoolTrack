#!/bin/bash
# ============================================================================
# SchoolTrack — Lancement rapide pour demo locale
# Usage : cd demo && bash start-demo.sh
# ============================================================================

set -e

DEMO_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$DEMO_DIR/.." && pwd)"

echo "============================================="
echo "  SchoolTrack — Demarrage demo locale"
echo "============================================="
echo ""

# ---------- 1. PostgreSQL via Docker ----------
echo "[1/4] Demarrage PostgreSQL..."
cd "$DEMO_DIR"
docker compose -f docker-compose.dev.yml up -d

echo "     Attente que PostgreSQL soit pret..."
until docker exec schooltrack_db_dev pg_isready -U schooltrack > /dev/null 2>&1; do
    sleep 1
done
echo "     [OK] PostgreSQL pret"
echo ""

# ---------- 2. Appliquer les migrations ----------
echo "[2/4] Application des migrations..."
cd "$PROJECT_DIR/backend"
for migration in migrations/*.sql; do
    if [ -f "$migration" ]; then
        echo "     -> $(basename "$migration")"
        docker exec -i schooltrack_db_dev psql -U schooltrack -d schooltrack < "$migration" 2>/dev/null || true
    fi
done
echo "     [OK] Migrations appliquees"
echo ""

# ---------- 3. Seed des donnees de demo ----------
echo "[3/4] Injection des donnees de demo..."
cd "$PROJECT_DIR/backend"
python "$DEMO_DIR/seed_demo.py"
echo ""

# ---------- 4. Instructions de lancement ----------
echo "============================================="
echo "  PRET ! Ouvrir 3 terminaux :"
echo "============================================="
echo ""
echo "  Terminal 1 — Backend API :"
echo "    cd $PROJECT_DIR/backend"
echo "    python -m uvicorn app.main:app --reload --host 0.0.0.0 --port 8000"
echo ""
echo "  Terminal 2 — Dashboard Web (Direction) :"
echo "    cd $PROJECT_DIR/flutter_web_dashboard"
echo "    flutter run -d chrome"
echo ""
echo "  Terminal 3 — App Mobile (Enseignant) :"
echo "    cd $PROJECT_DIR/flutter_teacher_app"
echo "    flutter run"
echo ""
echo "  API docs : http://localhost:8000/api/docs"
echo ""
echo "  Comptes :"
echo "    admin@schooltrack.be    / Admin123!    (Direction)"
echo "    teacher@schooltrack.be  / Teacher123!  (Enseignant)"
echo "============================================="
