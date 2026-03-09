# Contexte troubleshooting — Demo SchoolTrack

Copier-coller ce fichier dans l'IA pour qu'elle puisse t'aider en cas de probleme.

---

## Projet

SchoolTrack — Gestion automatisee des presences pour sorties scolaires (offline-first).
TFE Bachelier IT EPHEC. Dev: Mohamed Mokhtar El Mazani.

## Stack

- **Backend** : FastAPI (Python 3.13) + SQLAlchemy + PostgreSQL (Docker)
- **Frontend Web** : Flutter Web (Dashboard Direction)
- **Frontend Mobile** : Flutter Android (App Enseignant)
- **Infra** : Docker Compose (PostgreSQL seul pour la demo)

## Structure du projet

```
TFE_SchoolTrack/
├── backend/
│   ├── app/
│   │   ├── main.py              (FastAPI app, CORS, routers)
│   │   ├── config.py            (Settings via .env)
│   │   ├── database.py          (SQLAlchemy engine, SessionLocal)
│   │   ├── dependencies.py      (get_current_user, require_role, log_audit)
│   │   ├── models/              (User, Student, Trip, Assignment, Checkpoint, Attendance, etc.)
│   │   ├── schemas/             (Pydantic schemas)
│   │   ├── services/            (auth, trip, class, assignment, checkpoint, offline, sync, crypto)
│   │   └── routers/             (auth, users, students, trips, classes, tokens, checkpoints, sync, audit)
│   ├── .env                     (DATABASE_URL, SECRET_KEY, ENCRYPTION_KEY, SMTP)
│   ├── init.sql                 (Schema PostgreSQL v4.2 complet + 2 users seed)
│   └── migrations/              (5 migrations incrementales)
├── flutter_web_dashboard/
│   └── lib/
│       ├── core/
│       │   ├── api/api_client.dart   (HTTP client, authToken statique)
│       │   └── constants.dart        (kApiBaseUrl = http://localhost:8000 par defaut)
│       └── features/                 (auth, students, classes, trips, tokens, users, audit)
├── flutter_teacher_app/
│   └── lib/
│       ├── core/
│       │   ├── api/api_client.dart   (HTTP client mobile)
│       │   └── constants.dart        (kApiBaseUrl = http://192.168.1.2:8000)
│       └── features/                 (auth, trips, scan)
├── demo/
│   ├── docker-compose.dev.yml   (PostgreSQL seul, port 5432 expose)
│   ├── seed_demo.py             (25 eleves, 2 voyages, tokens, checkpoints, presences)
│   └── DEMO-GUIDE.md            (commandes + scenario)
└── docker-compose.yml           (production: Traefik + API + PostgreSQL + pgAdmin)
```

## Commandes de lancement (demo)

```bash
# 1. PostgreSQL
cd demo
docker compose -f docker-compose.dev.yml up -d

# 2. Seed (depuis backend/)
cd ../backend
python ../demo/seed_demo.py

# 3. Backend API
cd backend
python -m uvicorn app.main:app --reload --host 0.0.0.0 --port 8000

# 4. Dashboard Web
cd flutter_web_dashboard
flutter run -d chrome

# 5. App Mobile
cd flutter_teacher_app
flutter run
```

## Comptes de connexion

| Email | Mot de passe | Role |
|-------|-------------|------|
| admin@schooltrack.be | Admin123! | DIRECTION |
| teacher@schooltrack.be | Teacher123! | TEACHER |
| marie.lejeune@schooltrack.be | Teacher123! | TEACHER |
| obs@schooltrack.be | Observer123! | OBSERVER |

## Base de donnees

- **PostgreSQL 16** dans Docker, container `schooltrack_db_dev`
- Schema cree par `init.sql` (v4.2) au premier lancement du container
- Tables principales : users, students, classes, class_students, trips, trip_students, tokens, assignments, checkpoints, attendances, audit_logs
- Les colonnes `first_name`, `last_name`, `email` (students + users) et `totp_secret` sont **chiffrees AES-256-GCM** via le TypeDecorator `EncryptedString`
- DATABASE_URL dans `.env` : `postgresql://schooltrack:schooltrack_dev@localhost:5432/schooltrack`

## API endpoints principaux

- `POST /api/v1/auth/login` — Login (email + password + totp optionnel)
- `GET /api/v1/trips` — Liste des voyages
- `GET /api/v1/trips/{id}/offline-data` — Bundle offline pour l'app mobile
- `GET /api/v1/students` — Liste eleves
- `GET /api/v1/students/{id}/data-export` — Export RGPD
- `POST /api/v1/tokens/assign` — Assigner un bracelet
- `POST /api/v1/trips/{id}/checkpoints` — Creer un checkpoint
- `GET /api/v1/audit/logs` — Logs d'audit
- Swagger : http://localhost:8000/api/docs

## CORS

Configure dans `main.py` avec regex : `https?://(localhost|127\.0\.0\.1|192\.168\.\d+\.\d+)(:\d+)?`
Autorise localhost + reseau local 192.168.x.x.

## Problemes connus et solutions

### PostgreSQL "Connection refused" sur port 5432
- Verifier que Docker Desktop est demarre
- Verifier que le container tourne : `docker ps`
- Verifier le port mapping : doit afficher `0.0.0.0:5432->5432/tcp` (pas juste `5432/tcp`)
- Si pas de mapping : `docker rm -f schooltrack_db_dev` puis relancer `docker compose -f docker-compose.dev.yml up -d`

### App mobile "Impossible de contacter le serveur" / Timeout
- Le telephone doit etre sur le **meme Wi-Fi** que le PC
- Couper les **donnees mobiles** (4G/5G)
- Verifier l'IP dans `flutter_teacher_app/lib/core/constants.dart` (kApiBaseUrl)
- Le backend doit tourner avec `--host 0.0.0.0` (pas juste localhost)
- Android bloque HTTP par defaut : `android:usesCleartextTraffic="true"` doit etre dans AndroidManifest.xml
- Tester depuis le navigateur du tel : `http://<IP>:8000/api/health`
- Pare-feu Windows : `New-NetFirewallRule -DisplayName "SchoolTrack API" -Direction Inbound -Port 8000 -Protocol TCP -Action Allow`

### "column X does not exist" (UndefinedColumn)
- La BDD n'a pas les dernieres colonnes → appliquer les migrations :
  ```bash
  cd backend
  for f in migrations/*.sql; do docker exec -i <container_name> psql -U schooltrack -d schooltrack < "$f"; done
  ```
- Ou reset complet : `docker compose -f docker-compose.dev.yml down -v` puis `up -d` (repart de init.sql)

### "departure_date does not exist" sur export RGPD
- Bug corrige : la colonne s'appelle `date` (pas `departure_date`/`return_date`) dans la table trips
- Fichier : `backend/app/routers/students.py` ~ligne 188

### Donnees de demo absentes apres reset
- Relancer le seed : `cd backend && python ../demo/seed_demo.py`
- Si "Des donnees existent deja" : faire un reset complet (down -v + up -d) avant

### Flutter "kApiBaseUrl" ne change pas apres modification
- Les constantes Dart sont compilees → un hot reload ne suffit pas
- Il faut arreter et relancer `flutter run` (full rebuild)

### bcrypt / passlib incompatible
- Le projet utilise `bcrypt` directement (pas passlib) dans `auth_service.py`

### Dashboard Web ne se connecte pas a l'API
- Verifier que le backend tourne sur port 8000
- kApiBaseUrl est configurable via `--dart-define=API_BASE_URL=http://...` ou defaut `http://localhost:8000`

## Reset complet de la demo

```bash
cd demo
docker compose -f docker-compose.dev.yml down -v   # Supprime le volume PostgreSQL
docker compose -f docker-compose.dev.yml up -d      # Recree la BDD depuis init.sql
# Attendre ~5s
cd ../backend
python ../demo/seed_demo.py                         # Reinjecte les donnees de demo
```
