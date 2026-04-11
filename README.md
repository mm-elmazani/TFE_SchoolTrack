# SchoolTrack

> Gestion automatisée et offline-first des présences pour voyages scolaires  
> TFE — Bachelier en Technologies de l'Informatique · EPHEC · 2025-2026  
> Développeur : Mohamed Mokhtar El Mazani

![Flutter](https://img.shields.io/badge/Flutter-3.11-blue?logo=flutter)
![FastAPI](https://img.shields.io/badge/FastAPI-0.115-green?logo=fastapi)
![Python](https://img.shields.io/badge/Python-3.13-blue?logo=python)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-16-blue?logo=postgresql)
![Docker](https://img.shields.io/badge/Docker-Compose-blue?logo=docker)
![Tests](https://img.shields.io/badge/Tests-481%20React%20%2B%2011%20Flutter-brightgreen)
![License](https://img.shields.io/badge/Licence-MIT-lightgrey)

---

## Présentation

**SchoolTrack** permet aux enseignants de gérer les présences des élèves lors de sorties scolaires, même sans connexion réseau. L'application Flutter mobile scanne les bracelets NFC et les QR codes des élèves en mode entièrement offline, puis synchronise les données dès que le réseau est disponible.

**Fonctionnalités principales :**
- Scan hybride NFC + QR Code (assignation physique et digitale)
- Mode offline-first — aucun réseau requis pendant la sortie
- Synchronisation automatique avec retry et idempotence
- Dashboard web React pour la direction de l'école
- Multi-tenancy — isolation stricte par école
- 2FA (TOTP App + Email OTP)
- Chiffrement AES-256 de la base SQLite locale

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  ENSEIGNANT (terrain)          DIRECTION (bureau)                │
│                                                                 │
│  ┌──────────────┐              ┌──────────────────────────────┐ │
│  │ App Flutter  │◄──NFC/QR──► │  Dashboard React + Tailwind  │ │
│  │   Android    │              │  (Nginx · dashboard.*)       │ │
│  │  SQLite AES  │              └──────────────┬───────────────┘ │
│  └──────┬───────┘                             │                 │
│         │  HTTPS (sync offline→online)        │ HTTPS           │
│         ▼                                     ▼                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              FastAPI (Python 3.13)                       │   │
│  │   /api/v1/*  ·  /api/sync/*  ·  /api/docs (Swagger)    │   │
│  └─────────────────────────┬───────────────────────────────┘   │
│                             │                                   │
│                    ┌────────▼────────┐                          │
│                    │   PostgreSQL 16  │                          │
│                    │  (multi-tenant) │                          │
│                    └─────────────────┘                          │
│                                                                 │
│  Infrastructure : Docker Compose · Traefik · Let's Encrypt      │
└─────────────────────────────────────────────────────────────────┘
```

> Voir [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) pour les diagrammes de séquence détaillés (scan offline, synchronisation, cycle de vie tokens).

---

## Stack technique

| Couche | Technologie |
|--------|-------------|
| App mobile enseignants | Flutter 3.11 · Dart · SQLite AES-256 (SQLCipher) |
| Dashboard direction | React 18 · TypeScript · Tailwind CSS · Vite |
| API REST | FastAPI 0.115 · Python 3.13 · SQLAlchemy · Pydantic |
| Base de données centrale | PostgreSQL 16 |
| Base de données locale | SQLite 3 chiffré (sqflite_sqlcipher) |
| Infrastructure | Docker Compose · Traefik v3 · Nginx |
| Authentification | JWT (access + refresh) · 2FA TOTP/Email |
| Tests | Pytest · Vitest · Flutter integration_test |

---

## Prérequis

| Outil | Version minimale |
|-------|-----------------|
| Docker Desktop | 24.x |
| Docker Compose | 2.x |
| Flutter SDK | 3.11.0 |
| Python | 3.13 |
| Node.js | 20.x |
| Android Studio | Hedgehog+ (pour l'émulateur) |

---

## Installation et lancement en développement

### 1. Cloner le dépôt

```bash
git clone https://github.com/mm-elmazani/TFE_SchoolTrack.git
cd TFE_SchoolTrack
```

### 2. Configurer les variables d'environnement

```bash
cp .env.example .env
# Éditer .env si nécessaire (les valeurs par défaut suffisent pour le dev)
```

Variables clés du fichier `.env` :

| Variable | Valeur dev par défaut | Description |
|----------|-----------------------|-------------|
| `POSTGRES_DB` | `schooltrack` | Nom de la base PostgreSQL |
| `POSTGRES_USER` | `schooltrack` | Utilisateur PostgreSQL |
| `POSTGRES_PASSWORD` | `admin` | Mot de passe PostgreSQL |
| `SECRET_KEY` | *(à changer)* | Clé de signature JWT — **obligatoirement longue et aléatoire en prod** |
| `ALGORITHM` | `HS256` | Algorithme JWT |
| `ACCESS_TOKEN_EXPIRE_MINUTES` | `30` | Durée de validité du token d'accès |
| `DATABASE_URL` | `postgresql://schooltrack:...` | URL complète de connexion à PostgreSQL |

Pour le dashboard React, créer `react_dashboard/.env.local` :

```bash
VITE_API_URL=http://localhost:8000
```

### 3. Démarrer l'API et la base de données

```bash
docker compose up -d
```

L'API est disponible sur `http://localhost:8000`.  
La documentation Swagger est accessible sur [`http://localhost:8000/api/docs`](http://localhost:8000/api/docs).

### 4. Démarrer le dashboard React (dev)

```bash
cd react_dashboard
npm install
npm run dev
# → http://localhost:5173
```

### 5. Lancer l'application Flutter mobile

```bash
cd flutter_teacher_app
flutter pub get
flutter run                   # sur émulateur ou appareil connecté
```

---

## Comptes de test (environnement dev)

| Email | Mot de passe | Rôle |
|-------|-------------|------|
| `admin@schooltrack.be` | `Admin123!` | DIRECTION |
| `teacher@schooltrack.be` | `Teacher123!` | TEACHER |

---

## Tests

### Tests unitaires — React (Vitest)

```bash
cd react_dashboard
npm test                      # run + watch
npm run coverage              # rapport HTML dans coverage/
```

Couverture actuelle : **80.26 % (481 tests, 0 failures)**

### Tests unitaires — Flutter

```bash
cd flutter_teacher_app
flutter test test/
```

### Tests d'intégration offline — Flutter (US 7.2)

Sans émulateur (VM, CI) :
```bash
cd flutter_teacher_app
flutter test test/integration/offline_sync_test.dart
```

Sur émulateur Android :
```bash
flutter test integration_test/offline_sync_test.dart -d <device-id>
```

### Tests unitaires — Backend FastAPI (Pytest)

```bash
cd backend
pytest --cov=app --cov-report=html
```

### Tests de charge (Locust)

```bash
cd backend
locust -f tests/locustfile.py --host=http://localhost:8000
# → http://localhost:8089 (interface web)
```

---

## Structure du projet

```
TFE_SchoolTrack/
├── backend/                    # API FastAPI (Python)
│   ├── app/
│   │   ├── models/             # Modèles SQLAlchemy
│   │   ├── schemas/            # Schémas Pydantic
│   │   ├── routers/            # Endpoints REST
│   │   └── services/           # Logique métier
│   └── tests/                  # Tests Pytest
├── flutter_teacher_app/        # App mobile Flutter (Android)
│   ├── lib/
│   │   ├── core/               # API client, SQLite, services
│   │   └── features/           # Auth, trips, scan, sync
│   ├── test/                   # Tests unitaires + intégration
│   └── integration_test/       # Tests intégration (émulateur)
├── react_dashboard/            # Dashboard React + Tailwind
│   ├── src/features/           # Auth, trips, students, tokens…
│   └── src/shared/             # Composants partagés, hooks
├── docs/                       # Documentation technique
│   ├── ARCHITECTURE.md         # Diagrammes de séquence (Mermaid)
│   ├── DEPLOY-PRODUCTION.md    # Guide de déploiement VPS
│   ├── PERFORMANCE.md          # Rapport tests de charge
│   └── SECURITY.md             # Architecture de sécurité
├── docker-compose.yml          # Stack de développement
├── docker-compose.prod.yml     # Stack de production
└── .env.example                # Variables d'environnement (modèle)
```

---

## Déploiement en production

Voir [`docs/DEPLOY-PRODUCTION.md`](docs/DEPLOY-PRODUCTION.md) pour la procédure complète (VPS Debian, Docker Compose, Traefik, Let's Encrypt, SMTP, backups).

---

## Documentation technique

| Document | Description |
|----------|-------------|
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | Diagrammes de séquence — scan offline, sync, tokens |
| [`docs/DEPLOY-PRODUCTION.md`](docs/DEPLOY-PRODUCTION.md) | Guide de déploiement VPS complet |
| [`docs/SECURITY.md`](docs/SECURITY.md) | Architecture de sécurité et chiffrement |
| [`docs/PERFORMANCE.md`](docs/PERFORMANCE.md) | Rapport tests de charge Locust |
| [`docs/PRIVACY-POLICY.md`](docs/PRIVACY-POLICY.md) | Politique de confidentialité RGPD |
| [`CONTRIBUTING.md`](CONTRIBUTING.md) | Guide de contribution et conventions |
| [Swagger `/api/docs`](http://localhost:8000/api/docs) | Documentation API interactive |

---

## Licence

MIT — voir [`LICENSE`](LICENSE)
