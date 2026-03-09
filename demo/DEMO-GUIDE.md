# SchoolTrack — Guide de demo locale

## 1. Prerequis

- Docker Desktop demarre
- Python 3.13 + venv backend active
- Flutter SDK installe

## 2. Lancer l'infrastructure

```bash
# PostgreSQL (init.sql cree le schema complet automatiquement)
cd demo
docker compose -f docker-compose.dev.yml up -d

# Attendre ~5s que PostgreSQL soit pret, puis injecter les donnees de demo
cd ../backend
python ../demo/seed_demo.py
```

## 3. Lancer les applications (3 terminaux)

**Terminal 1 — API FastAPI :**
```bash
cd backend
python -m uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

**Terminal 2 — Dashboard Web (Direction) :**
```bash
cd flutter_web_dashboard
flutter run -d chrome
```

**Terminal 3 — App Mobile (Enseignant) :**
```bash
cd flutter_teacher_app
flutter run
```

## 4. Comptes de connexion

| Email | Mot de passe | Role |
|-------|-------------|------|
| admin@schooltrack.be | Admin123! | DIRECTION |
| teacher@schooltrack.be | Teacher123! | TEACHER |
| obs@schooltrack.be | Observer123! | OBSERVER |

## 5. Scenario de demo

### A. Dashboard Web — Connexion Direction (admin@schooltrack.be)

1. **Login** — Montrer l'ecran de connexion, s'authentifier
2. **Eleves** (`/students`) — Liste des 25 eleves, recherche, tri alphabetique
3. **Import CSV** (`/students/import`) — Montrer l'upload d'un fichier CSV
4. **Classes** (`/classes`) — 2 classes (3TI-A, 3TI-B), voir les eleves assignes
5. **Voyages** (`/trips`) — 2 voyages : Bruxelles (ACTIVE) + Anvers (PLANNED), stats (nb eleves, checkpoints)
6. **Tokens/Bracelets** (`/tokens`) — Selectionner le voyage Bruxelles, voir les 25 bracelets assignes, montrer assign/reassign
7. **Gestion utilisateurs** (`/users`) — Creer/supprimer des comptes (reserve Direction)
8. **Audit logs** (`/audit`) — Filtrer par action, par utilisateur, voir le detail JSON
9. **Permissions** — Se deconnecter, se reconnecter en tant qu'OBSERVER → montrer que les menus d'ecriture sont masques

### B. App Mobile — Connexion Enseignant (teacher@schooltrack.be)

1. **Login** — Connexion mobile
2. **Liste voyages** — Voir le voyage Bruxelles (ACTIVE) avec badge de telechargement offline
3. **Selection checkpoint** — Selectionner "Arrivee Parlement EU" (ACTIVE) ou creer un nouveau
4. **Scan** — Montrer l'ecran de scan (QR / NFC), scanner un code si dispo
5. **Liste presences** — Voir les presences du checkpoint en temps reel, montrer le marquage manuel

### C. Points forts a souligner

- **Offline-first** : les donnees de voyage sont telechargees localement, le scan fonctionne sans connexion
- **Securite** : JWT + 2FA optionnel, chiffrement AES-256 des donnees sensibles (noms, emails), audit RGPD
- **Permissions** : matrice de roles (Direction, Teacher, Observer) — UI conditionnelle
- **Architecture** : FastAPI + PostgreSQL + Flutter (Web + Mobile), Docker

## 6. URL utiles

- Swagger API : http://localhost:8000/api/docs
- Health check : http://localhost:8000/api/health

## 7. Reset complet (si besoin)

```bash
cd demo
docker compose -f docker-compose.dev.yml down -v
docker compose -f docker-compose.dev.yml up -d
# Attendre ~5s...
cd ../backend
python ../demo/seed_demo.py
```
