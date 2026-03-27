# Plan déploiement production — SchoolTrack
**Deadline : 2026-03-30**
**VPS IP : 81.88.25.75 (One.com)**
**Domaine : schooltrack.yourschool.be**

---

## Sous-domaines DNS (déjà configurés)

| Sous-domaine | Service |
|---|---|
| `api.schooltrack.yourschool.be` | FastAPI backend |
| `dashboard.schooltrack.yourschool.be` | React dashboard |
| `pgadmin.schooltrack.yourschool.be` | PgAdmin |
| `app.schooltrack.yourschool.be` | (réservé APK / futur) |

---

## PHASE 1 — US 6.6 : Isolation des données par école
> **Prérequis au déploiement. À faire en local, puis déployer.**

### Objectif
Ajouter une table `schools`. Lier chaque user/classe/élève/sortie à une école.
Bénéfice : isolation données client ↔ données dev, sans changer d'environnement.

### Design choisi
- Row-level multi-tenancy (une seule DB, filtre par `school_id`)
- `school_id` ajouté sur les tables parentes : `users`, `classes`, `students`, `trips`
- Les tables enfants (assignments, checkpoints, etc.) héritent du scope via la jointure parent
- `school_id` embarqué dans le JWT → toutes les requêtes scoped automatiquement

### 1.1 — Migration SQL (fichier `011_add_schools_multitenancy.sql`)
- [ ] Créer table `schools` (id UUID, name, slug UNIQUE, is_active, created_at)
- [ ] Ajouter colonne `school_id UUID` nullable dans `users`
- [ ] Ajouter colonne `school_id UUID` nullable dans `classes`
- [ ] Ajouter colonne `school_id UUID` nullable dans `students`
- [ ] Ajouter colonne `school_id UUID` nullable dans `trips`
- [ ] Ajouter FK `school_id → schools(id)` sur chaque table
- [ ] Insérer les 2 schools seed : `dev` (slug: dev) + `client` (slug: client)
- [ ] Mettre à jour les users seed existants → lier à school "dev"
- [ ] Mettre à jour classes/students/trips existants → lier à school "dev"
- [ ] Passer les colonnes NOT NULL après update

### 1.2 — Modèle SQLAlchemy (`app/models/school.py`)
- [ ] Créer modèle `School` (id, name, slug, is_active, created_at)
- [ ] Ajouter `school_id` + relationship dans `User`, `SchoolClass`, `Student`, `Trip`

### 1.3 — Schémas Pydantic (`app/schemas/school.py`)
- [ ] `SchoolCreate`, `SchoolRead`, `SchoolList`

### 1.4 — Router (`app/routers/schools.py`)
- [ ] `GET /api/v1/schools` — liste (rôle DIRECTION uniquement)
- [ ] `POST /api/v1/schools` — créer école (admin global uniquement)
- [ ] Brancher dans `main.py`

### 1.5 — Auth : JWT + dependency
- [ ] Ajouter `school_id` dans le payload JWT (auth_service.py `create_access_token`)
- [ ] Mettre à jour `get_current_user` dans `dependencies.py` → expose `current_user.school_id`
- [ ] Tous les services : passer `school_id` en filtre sur les requêtes DB

### 1.6 — Services à mettre à jour
- [ ] `trip_service.py` → filtre `school_id`
- [ ] `class_service.py` → filtre `school_id`
- [ ] `student_import.py` → assigne `school_id`
- [ ] `assignment_service.py` → via trip scoped
- [ ] `checkpoint_service.py` → via trip scoped
- [ ] `sync_service.py` → vérifier cohérence school

### 1.7 — Seed mis à jour
- [ ] `init.sql` : 2 schools + users liés à school "dev"

### 1.8 — Vérification locale
- [ ] Login admin (school dev) → ne voit pas les données school client
- [ ] Login admin (school client) → ne voit pas les données school dev
- [ ] Créer un enseignant dans school client → inaccessible depuis school dev

---

## PHASE 2 — docker-compose.prod.yml
> **Adapter le compose pour la prod (ajout React dashboard + Portainer, fix domaines).**

### 2.1 — Fichier `docker-compose.prod.yml`
- [ ] Reprendre `docker-compose.yml` comme base
- [ ] Fixer les labels Traefik (utiliser des vars séparées par service) :
  - `API_DOMAIN=api.schooltrack.yourschool.be`
  - `DASHBOARD_DOMAIN=dashboard.schooltrack.yourschool.be`
  - `PGADMIN_DOMAIN=pgadmin.schooltrack.yourschool.be`
  - `PORTAINER_DOMAIN=portainer.schooltrack.yourschool.be` *(ajouter record DNS A)*
- [ ] Désactiver le port 8080 Traefik dashboard (sécurité prod)
- [ ] Ajouter service **React dashboard** (image Nginx, build statique)
- [ ] Ajouter service **Portainer CE**
- [ ] Supprimer `ports: 5432:5432` postgres (accès interne uniquement)
- [ ] Ajouter `restart: always` partout

### 2.2 — Fichier `.env.prod` (ne pas committer)
```
POSTGRES_DB=schooltrack
POSTGRES_USER=schooltrack
POSTGRES_PASSWORD=<mot_de_passe_fort>
SECRET_KEY=<clé_jwt_256bits>
ENCRYPTION_KEY=<clé_aes_256bits>
ACME_EMAIL=admin@schooltrack.be
API_DOMAIN=api.schooltrack.yourschool.be
DASHBOARD_DOMAIN=dashboard.schooltrack.yourschool.be
PGADMIN_DOMAIN=pgadmin.schooltrack.yourschool.be
PGADMIN_EMAIL=admin@schooltrack.be
PGADMIN_PASSWORD=<mot_de_passe_fort>
```

### 2.3 — React dashboard build
- [ ] Mettre à jour `react_dashboard/.env.production` :
  `VITE_API_URL=https://api.schooltrack.yourschool.be`
- [ ] Vérifier tous les `axios.defaults.baseURL` / `api/client.ts`
- [ ] Créer `react_dashboard/Dockerfile` (build multi-stage → Nginx)
- [ ] Tester build local : `docker build -t schooltrack-dashboard ./react_dashboard`

---

## PHASE 3 — Setup VPS
> **Exécuté par toi sur le VPS. Vérifier chaque étape avant de continuer.**

### 3.1 — Vérification initiale (SSH)
```bash
ssh root@81.88.25.75
docker --version          # doit être ≥ 24.x
docker compose version    # doit être ≥ 2.x
docker ps                 # voir containers actifs
```
- [ ] Docker installé → sinon : `curl -fsSL https://get.docker.com | sh`
- [ ] Docker Compose v2 → sinon : intégré dans Docker Desktop ou plugin

### 3.2 — Portainer CE
```bash
docker volume create portainer_data
docker run -d \
  -p 9443:9443 \
  --name portainer \
  --restart=always \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v portainer_data:/data \
  portainer/portainer-ce:latest
```
- [ ] Ajouter label Traefik pour `portainer.schooltrack.yourschool.be`
- [ ] Ajouter record DNS A pour portainer (81.88.25.75) si besoin

### 3.3 — Cloner le repo sur le VPS
```bash
cd /opt
git clone https://github.com/mm-elmazani/TFE_SchoolTrack.git schooltrack
cd schooltrack
```

### 3.4 — Créer `.env.prod` sur le VPS
- [ ] Copier `.env.prod.example` → `.env.prod`
- [ ] Remplir toutes les valeurs (passwords forts, clés générées)

### 3.5 — Build et démarrage
```bash
docker compose -f docker-compose.prod.yml --env-file .env.prod up -d --build
docker compose -f docker-compose.prod.yml ps   # tous UP ?
docker logs schooltrack_api --tail 50          # vérifier démarrage API
```

---

## PHASE 4 — DB : migrations + seed
> **Exécuté après que l'API soit UP.**

### 4.1 — Appliquer les migrations SQL
```bash
# Depuis le VPS, dans le container API ou directement psql
docker exec -it schooltrack_db psql -U schooltrack -d schooltrack
# Puis exécuter chaque fichier migrations/ dans l'ordre (001 → 011)
```
- [ ] Migrations 001 → 011 appliquées
- [ ] Vérifier tables : `\dt` dans psql

### 4.2 — Seed initial
```bash
docker exec -it schooltrack_api python -m app.scripts.seed
# ou via init.sql si seed intégré
```
- [ ] School "dev" créée (slug: dev)
- [ ] School "client" créée (slug: client)
- [ ] Admin + teacher créés dans school "client"

---

## PHASE 5 — Monitoring et health checks (US 8.4)
> **À faire pendant ou juste après le déploiement.**

### 5.1 — Endpoint `/health` (backend)
- [ ] Ajouter `GET /health` dans FastAPI → vérifie connexion PostgreSQL + retourne statut JSON
- [ ] Exemple : `{"status": "ok", "db": "connected", "version": "1.0.0"}`

### 5.2 — Docker health checks
- [ ] Ajouter directive `healthcheck` dans `docker-compose.prod.yml` pour chaque service
- [ ] Vérifier que tous les containers passent en `healthy` : `docker ps`

### 5.3 — Monitoring externe
- [ ] Créer compte UptimeRobot (gratuit) ou Healthchecks.io
- [ ] Ajouter monitor sur `https://api.schooltrack.yourschool.be/health`
- [ ] Configurer alerte email si indisponibilité > 5 min

### 5.4 — Traefik dashboard sécurisé
- [ ] Activer dashboard Traefik avec authentification basique (basic auth middleware)
- [ ] Accessible uniquement via IP ou sous-domaine restreint

---

## PHASE 6 — Backup PostgreSQL (US 8.3)
> **À configurer sur le VPS après déploiement.**

### 6.1 — Script de backup
- [ ] Créer script `scripts/backup.sh` : `pg_dump` → fichier `.sql.gz` daté
- [ ] Stocker dans volume séparé `/backups/`
- [ ] Rotation automatique : supprimer les backups > 30 jours

### 6.2 — Automatisation (cron)
```bash
# Sur le VPS, dans crontab -e :
0 2 * * * /opt/schooltrack/scripts/backup.sh >> /var/log/schooltrack-backup.log 2>&1
```
- [ ] Backup quotidien à 2h du matin
- [ ] Tester restauration depuis un backup : `pg_restore`
- [ ] Documenter procédure dans `docs/BACKUP.md`

---

## PHASE 7 — Vérification complète (Jour 4)
> **Checklist fonctionnelle à valider avant de livrer au client.**

### HTTPS
- [ ] `https://api.schooltrack.yourschool.be/docs` → Swagger accessible
- [ ] `https://dashboard.schooltrack.yourschool.be` → Login page OK
- [ ] `https://pgadmin.schooltrack.yourschool.be` → pgAdmin accessible
- [ ] Certificats Let's Encrypt valides (cadenas vert)

### Fonctionnel
- [ ] Login admin (school client) → Dashboard
- [ ] Créer une classe + importer des élèves
- [ ] Créer une sortie + assigner tokens
- [ ] Pointer présences (simuler depuis l'API ou app)
- [ ] Test mot de passe oublié (email reçu ?)
- [ ] Test 2FA (APP ou EMAIL)
- [ ] **Isolation école** : se connecter avec un compte école dev → données client invisibles

### Sécurité
- [ ] Port 5432 PostgreSQL non exposé publiquement : `nmap -p 5432 81.88.25.75`
- [ ] Traefik dashboard (8080) non exposé publiquement
- [ ] TLS 1.3 minimum : `curl -v --tlsv1.3 https://api.schooltrack.yourschool.be`
- [ ] Endpoint `/health` répond en < 500ms

---

## PHASE 8 — Flutter APK + Play Store (US 8.2)
> **Indépendant, peut être fait en parallèle.**

- [ ] Mettre à jour URL API dans le code Flutter → `https://api.schooltrack.yourschool.be`
- [ ] Rebuild : `flutter build appbundle --release` (AAB pour Play Store)
- [ ] Configurer keystore de production (clé sécurisée, non versionnée)
- [ ] Tester APK sur appareil physique
- [ ] Créer compte Google Developer (25$ one-time) si pas encore fait
- [ ] Préparer fiche Play Store (captures min. 2, description, politique de confidentialité)
- [ ] Soumettre AAB → Play Store (délai review ~24-72h)

---

## PHASE 9 — CI/CD GitHub Actions (US 8.5)
> **Après que tout soit stable en prod. Non bloquant pour le déploiement initial.**

- [ ] Créer `.github/workflows/ci.yml` → tests backend (`pytest`) à chaque push sur `develop`/`main`
- [ ] Échec si coverage < 80%
- [ ] Créer `.github/workflows/deploy.yml` → déploiement SSH sur VPS au merge sur `main`
- [ ] Stocker secrets dans GitHub Secrets (SSH key, .env vars)
- [ ] Badge CI dans README

---

## Résumé timeline

| Jour | Phases | Responsable |
|---|---|---|
| J1 (26/03) | Phase 1 — Multi-tenancy (migration + backend + services) | Dev |
| J2 (27/03) | Phase 2 — docker-compose.prod + React Dockerfile + backup script | Dev |
| J3 (28/03) | Phase 3+4+5 — VPS setup + déploiement + health + monitoring | Dev + IA |
| J4 (29/03) | Phase 6+7 — Backup cron + vérification complète | Dev + IA |
| J5 (30/03) | Buffer + Phase 8 Flutter APK | Dev |
| Après | Phase 9 — CI/CD GitHub Actions | Dev |

## Couverture EPIC 8

| US | Titre | Phase plan | Priorité |
|---|---|---|---|
| **US 6.6** | Isolation données par école (multi-tenancy) | Phase 1 | Bloquante |
| **US 8.1** | Déploiement VPS | Phase 2+3+4 | Bloquante |
| **US 8.2** | Play Store | Phase 8 | Haute |
| **US 8.3** | Backup PostgreSQL | Phase 6 | Haute |
| **US 8.4** | Monitoring + health | Phase 5 | Haute |
| **US 8.5** | CI/CD GitHub Actions | Phase 9 | Après prod |

---

## Notes techniques

- **Migrations** : fichiers SQL manuels dans `backend/migrations/` (pas Alembic)
- **Docker compose** : `docker-compose.prod.yml` séparé du dev compose
- **Secrets** : jamais dans le repo — `.env.prod` uniquement sur le VPS
- **DB prod** : repartir de zéro (clean), appliquer `init.sql` + migrations 001→011
