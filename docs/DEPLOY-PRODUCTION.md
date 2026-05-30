# SchoolTrack -- Guide de deploiement en production

> Document PRIVE -- ne pas partager publiquement
> Destinataires : Mohamed + assistant admin uniquement
> Version 1.0 (mars 2026)

---

## Table des matieres

1. [Pre-requis VPS](#1-pre-requis-vps)
2. [Installation initiale](#2-installation-initiale)
3. [Configuration .env production](#3-configuration-env-production)
4. [Lancement](#4-lancement)
5. [Verification post-deploiement](#5-verification-post-deploiement)
6. [Gestion des cles de chiffrement](#6-gestion-des-cles-de-chiffrement)
7. [Backups](#7-backups)
8. [Mise a jour (deploiement continu)](#8-mise-a-jour-deploiement-continu)
9. [Monitoring et logs](#9-monitoring-et-logs)
10. [Checklist securite](#10-checklist-securite)
11. [Pieges a eviter](#11-pieges-a-eviter)
12. [Depannage](#12-depannage)

---



### Installation Docker (si pas deja installe)

```bash
# Docker
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
# Se deconnecter et reconnecter pour appliquer le groupe

# Verifier
docker --version
docker compose version
```

### DNS

Configurer les enregistrements DNS **avant** le deploiement :

| Type | Nom | Valeur |
|------|-----|--------|
| A | `api.schooltrack.be` | IP du VPS |
| A | `pgadmin.schooltrack.be` | IP du VPS (meme IP) |

> Let's Encrypt a besoin que le DNS pointe deja vers le serveur pour
> generer les certificats. Si le DNS n'est pas encore configure,
> Traefik demarrera mais sans TLS.

---

## 2. Installation initiale

```bash
# Se connecter au VPS
ssh user@votre-vps

# Creer le dossier
sudo mkdir -p /opt/schooltrack
sudo chown $USER:$USER /opt/schooltrack
cd /opt/schooltrack

# Cloner le repo
git init
git remote add origin https://github.com/mm-elmazani/TFE_SchoolTrack.git
git pull origin main
```

---

## 3. Configuration .env production

**C'est l'etape la plus critique.** Creer le fichier `.env` a la racine du projet :

```bash
cd /opt/schooltrack
cp backend/.env .env   # Copier le template
nano .env              # Editer avec les vraies valeurs
```

### Contenu du `.env` production

```bash
# ============================================================
# SchoolTrack — PRODUCTION
# ============================================================

# ---------- PostgreSQL ----------
POSTGRES_DB=schooltrack
POSTGRES_USER=schooltrack
POSTGRES_PASSWORD=<MOT_DE_PASSE_FORT_32_CHARS>

# ---------- pgAdmin ----------
PGADMIN_EMAIL=admin@schooltrack.be
PGADMIN_PASSWORD=<MOT_DE_PASSE_PGADMIN>

# ---------- FastAPI ----------
DATABASE_URL=postgresql://schooltrack:<MEME_MDP_QUE_POSTGRES_PASSWORD>@postgres:5432/schooltrack
SECRET_KEY=<CLE_ALEATOIRE_64_CHARS>
ENCRYPTION_KEY=<CLE_ALEATOIRE_64_CHARS_DIFFERENTE>
ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=30
ENV=production

# ---------- Traefik ----------
API_DOMAIN=api.schooltrack.be
ACME_EMAIL=admin@schooltrack.be
TRAEFIK_DOMAIN=traefik.schooltrack.yourschool.be
# Genere avec : htpasswd -nB admin  (voir section 9 — Dashboard Traefik)
# Attention : les $ doivent etre doubles ($$) dans ce fichier .env
TRAEFIK_AUTH=admin:$$2y$$12$$<hash_a_generer>

# ---------- SMTP (Brevo) ----------
SMTP_HOST=smtp-relay.brevo.com
SMTP_PORT=587
SMTP_USERNAME=<votre_identifiant_brevo>
SMTP_PASSWORD=<votre_cle_smtp_brevo>
SMTP_FROM=noreply@schooltrack.be
SMTP_USE_TLS=true
```

### Generer les cles aleatoires

```bash
# SECRET_KEY (signature JWT) — 64 caracteres hex
python3 -c "import secrets; print(secrets.token_hex(32))"

# ENCRYPTION_KEY (chiffrement AES-256) — 64 caracteres hex
python3 -c "import secrets; print(secrets.token_hex(32))"

# POSTGRES_PASSWORD — 32 caracteres alphanumeriques
python3 -c "import secrets; print(secrets.token_urlsafe(24))"
```

> **IMPORTANT :** SECRET_KEY et ENCRYPTION_KEY doivent etre **differentes**.
> Ne reutilisez JAMAIS une cle pour deux usages differents.

### Securiser le fichier .env

```bash
chmod 600 .env           # Lisible uniquement par le proprietaire
chown $USER:$USER .env   # S'assurer du bon proprietaire
```

---

## 4. Lancement

```bash
cd /opt/schooltrack

# Premier lancement (build + demarrage)
docker compose up -d --build

# Verifier que tout tourne
docker compose ps

# Voir les logs
docker compose logs -f
```

### Resultat attendu de `docker compose ps`

```
NAME                  STATUS          PORTS
schooltrack_traefik   Up              0.0.0.0:80->80, 0.0.0.0:443->443
schooltrack_api       Up              8000/tcp
schooltrack_db        Up (healthy)    5432/tcp
schooltrack_pgadmin   Up              80/tcp
```

### Premiere connexion

1. Ouvrir `https://api.schooltrack.be/docs` -- documentation Swagger
2. Se connecter avec `admin@schooltrack.be` / `Admin123!`
3. **IMMEDIATEMENT** : changer le mot de passe admin via pgAdmin ou l'API

> **ATTENTION** : Les comptes seed (`init.sql`) ont des mots de passe connus.
> Changez-les IMMEDIATEMENT apres le premier deploiement.
> Voir la section [Pieges a eviter](#11-pieges-a-eviter).

---

## 5. Verification post-deploiement

Executer cette checklist apres chaque deploiement :

```bash
# 1. API repond
curl -s https://api.schooltrack.be/docs | head -5

# 2. TLS fonctionne (pas d'erreur certificat)
curl -vI https://api.schooltrack.be 2>&1 | grep "SSL certificate"

# 3. HTTP redirige vers HTTPS
curl -sI http://api.schooltrack.be | grep Location

# 4. Login fonctionne
curl -s -X POST https://api.schooltrack.be/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@schooltrack.be","password":"Admin123!"}' | python3 -m json.tool

# 5. Chiffrement fonctionne (verifier en base)
docker exec schooltrack_db psql -U schooltrack -d schooltrack \
  -c "SELECT first_name FROM users LIMIT 1;"
# → Doit afficher une chaine base64, PAS un prenom en clair

# 6. Pas de port expose inutilement
docker compose ps --format "table {{.Name}}\t{{.Ports}}"
```

---

## 6. Gestion des cles de chiffrement

### Cles critiques

| Cle | Si elle est perdue... | Si elle est compromise... |
|-----|----------------------|--------------------------|
| `ENCRYPTION_KEY` | **Toutes les donnees chiffrees sont PERDUES** (noms, prenoms, emails) | Rotation necessaire (voir ci-dessous) |
| `SECRET_KEY` | Tous les JWT actifs deviennent invalides (les users doivent se reconnecter) | Changer la cle, tous les users se reconnectent |
| `POSTGRES_PASSWORD` | Impossible de se connecter a la BDD | Changer le mdp PostgreSQL + docker compose |

### Sauvegarde des cles

```bash
# Creer un fichier de sauvegarde des cles (HORS du repo git)
mkdir -p ~/schooltrack-secrets
cp /opt/schooltrack/.env ~/schooltrack-secrets/.env.backup.$(date +%Y%m%d)
chmod 600 ~/schooltrack-secrets/*

# Optionnel : copier sur une machine locale
scp user@vps:~/schooltrack-secrets/.env.backup.* ./mes-sauvegardes/
```

> **Regle d'or** : le fichier `.env` doit exister a **minimum 2 endroits**.
> Si le VPS brule, vous devez pouvoir retrouver ENCRYPTION_KEY.
> Sans cette cle, les donnees en base sont IRRECUPERABLES.

### Rotation de la cle de chiffrement

Si ENCRYPTION_KEY est compromise ou par precaution periodique :

```bash
cd /opt/schooltrack

# 1. Arreter l'API (pour eviter des ecritures pendant la migration)
docker compose stop api

# 2. Sauvegarder la BDD
docker exec schooltrack_db pg_dump -U schooltrack schooltrack > backup_avant_rotation.sql

# 3. Dechiffrer avec l'ancienne cle
docker compose run --rm api python -m scripts.migrate_decrypt

# 4. Mettre a jour ENCRYPTION_KEY dans .env avec la nouvelle cle
nano .env

# 5. Re-chiffrer avec la nouvelle cle
docker compose run --rm api python -m scripts.migrate_encrypt

# 6. Redemarrer
docker compose up -d api

# 7. Verifier que l'API repond et les donnees sont accessibles
curl -s https://api.schooltrack.be/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@schooltrack.be","password":"Admin123!"}'
```

---

## 7. Backups

### Backup automatique (crontab)

```bash
# Creer le script de backup
cat > /opt/schooltrack/backup.sh << 'SCRIPT'
#!/bin/bash
set -euo pipefail

BACKUP_DIR="/opt/schooltrack/backups"
DATE=$(date +%Y%m%d_%H%M%S)
RETENTION_DAYS=30

mkdir -p "$BACKUP_DIR"

# Dump PostgreSQL
docker exec schooltrack_db pg_dump -U schooltrack schooltrack \
  | gzip > "$BACKUP_DIR/schooltrack_$DATE.sql.gz"

# Copier le .env (contient les cles)
cp /opt/schooltrack/.env "$BACKUP_DIR/env_$DATE.bak"
chmod 600 "$BACKUP_DIR/env_$DATE.bak"

# Supprimer les backups de plus de N jours
find "$BACKUP_DIR" -name "*.sql.gz" -mtime +$RETENTION_DAYS -delete
find "$BACKUP_DIR" -name "env_*.bak" -mtime +$RETENTION_DAYS -delete

echo "[$(date)] Backup OK: schooltrack_$DATE.sql.gz"
SCRIPT

chmod +x /opt/schooltrack/backup.sh
```

```bash
# Ajouter au crontab (backup quotidien a 3h du matin)
crontab -e
# Ajouter cette ligne :
0 3 * * * /opt/schooltrack/backup.sh >> /var/log/schooltrack-backup.log 2>&1
```

### Restaurer un backup

```bash
# 1. Arreter l'API
docker compose stop api

# 2. Restaurer la BDD
gunzip -c backups/schooltrack_20260307_030000.sql.gz \
  | docker exec -i schooltrack_db psql -U schooltrack schooltrack

# 3. Restaurer le .env si necessaire
cp backups/env_20260307_030000.bak /opt/schooltrack/.env

# 4. Redemarrer
docker compose up -d
```

### Backup hors site (recommande)

```bash
# Copier les backups vers une autre machine
rsync -avz /opt/schooltrack/backups/ user@backup-server:/backups/schooltrack/

# OU vers un stockage cloud (S3, Backblaze B2, etc.)
# Installer rclone et configurer un remote
rclone sync /opt/schooltrack/backups/ remote:schooltrack-backups/
```

---

## 8. Mise a jour (deploiement continu)

### Deployer une nouvelle version

```bash
cd /opt/schooltrack

# 1. Tirer les changements
git pull origin main

# 2. Rebuild et redemarrer (zero downtime si pas de migration)
docker compose up -d --build

# 3. Verifier
docker compose ps
docker compose logs -f api --tail=20
```

### Si une migration de BDD est necessaire

```bash
# Apres le pull, avant le restart
docker compose run --rm api python -m scripts.migrate_encrypt
docker compose up -d --build
```

### Rollback d'urgence

```bash
# Revenir au commit precedent
git log --oneline -5            # Trouver le commit stable
git checkout <commit-hash>      # Revenir a ce commit
docker compose up -d --build    # Redemarrer avec l'ancienne version
```

---

## 9. Monitoring et logs

### Voir les logs

```bash
# Tous les services
docker compose logs -f

# Un service specifique
docker compose logs -f api
docker compose logs -f postgres
docker compose logs -f traefik

# Les 50 dernieres lignes
docker compose logs --tail=50 api
```

### Verifier l'espace disque

```bash
# Espace disque general
df -h

# Espace Docker
docker system df

# Nettoyer les images inutilisees
docker system prune -f
```

### Verifier la sante de la BDD

```bash
# Nombre d'enregistrements
docker exec schooltrack_db psql -U schooltrack -d schooltrack \
  -c "SELECT 'students' as t, count(*) FROM students
      UNION ALL SELECT 'users', count(*) FROM users
      UNION ALL SELECT 'trips', count(*) FROM trips
      UNION ALL SELECT 'attendances', count(*) FROM attendances;"

# Taille de la BDD
docker exec schooltrack_db psql -U schooltrack -d schooltrack \
  -c "SELECT pg_size_pretty(pg_database_size('schooltrack'));"
```

---

### Dashboard Traefik (US 8.4)

Le dashboard Traefik permet de visualiser les routes, services et middlewares actifs.
Il est expose sur `https://traefik.schooltrack.yourschool.be` et protege par BasicAuth.

#### 1. Creer le DNS

Dans le panneau DNS de ton hebergeur, ajouter un enregistrement A :
```
traefik.schooltrack.yourschool.be → <IP_VPS>
```

#### 2. Generer le mot de passe htpasswd

```bash
# Sur le VPS — installer apache2-utils si absent
sudo apt-get install -y apache2-utils

# Generer le hash bcrypt (remplacer "admin" par le login voulu)
htpasswd -nB admin
# Exemple de sortie : admin:$2y$05$abc123...

# IMPORTANT : dans .env.prod, doubler TOUS les $ du hash
# $2y$05$abc  →  $$2y$$05$$abc
```

#### 3. Mettre a jour `.env.prod`

```bash
TRAEFIK_DOMAIN=traefik.schooltrack.yourschool.be
TRAEFIK_AUTH=admin:$$2y$$05$$<le_hash_avec_dollars_doubles>
```

#### 4. Redemarrer Traefik

```bash
docker compose -f docker-compose.prod.yml up -d traefik
```

#### 5. Verifier

Ouvrir `https://traefik.schooltrack.yourschool.be` → login BasicAuth → dashboard visible.

---

### Monitoring externe — UptimeRobot (US 8.4)

UptimeRobot surveille l'API toutes les 5 minutes et envoie une alerte email si elle tombe.

#### Setup (gratuit, 50 monitors inclus)

1. Creer un compte sur [uptimerobot.com](https://uptimerobot.com)
2. Cliquer **"Add New Monitor"**
3. Remplir :
   - **Monitor Type** : HTTP(s)
   - **Friendly Name** : SchoolTrack API
   - **URL** : `https://api.schooltrack.yourschool.be/api/health`
   - **Monitoring Interval** : 5 minutes
4. Dans **"Alert Contacts"** : ajouter ton email
5. Cliquer **"Create Monitor"**

#### Verification

- Le monitor doit passer en vert (UP) dans les 5 minutes
- Tester en coupant l'API : `docker stop schooltrack_api` → UptimeRobot envoie un email DOWN
- Relancer : `docker start schooltrack_api` → email UP recu

---

## 10. Checklist securite

### Avant le premier deploiement

- [ ] `.env` configure avec des cles **uniques et aleatoires**
- [ ] `.env` a les permissions `600`
- [ ] DNS pointe vers le VPS (pour Let's Encrypt)
- [ ] Firewall VPS : seuls les ports 22 (SSH), 80, 443 sont ouverts
- [ ] SSH par cle uniquement (desactiver l'auth par mot de passe)

### Apres le premier deploiement

- [ ] HTTPS fonctionne (pas d'avertissement certificat)
- [ ] HTTP redirige vers HTTPS
- [ ] Mot de passe `admin@schooltrack.be` change (pas `Admin123!`)
- [ ] Mot de passe `teacher@schooltrack.be` change (pas `Teacher123!`)
- [ ] Les donnees en base sont chiffrees (voir verification section 5)
- [ ] Le dashboard Traefik (port 8080) n'est PAS accessible depuis Internet
- [ ] pgAdmin accessible uniquement via HTTPS

### Regulierement (mensuel)

- [ ] Backups fonctionnent (verifier `/opt/schooltrack/backups/`)
- [ ] Verifier les logs d'audit (`audit_logs`) pour des activites suspectes
- [ ] Mettre a jour les images Docker (`docker compose pull`)
- [ ] Verifier l'espace disque (`df -h`)
- [ ] ENCRYPTION_KEY sauvegardee a 2+ endroits

---

## 11. Pieges a eviter

### 1. Comptes seed en clair dans init.sql

`init.sql` insere `admin@schooltrack.be` et `teacher@schooltrack.be` avec
des mots de passe **connus** et des noms en **clair** (pas chiffres).

**Solutions** :
- Apres le premier deploiement, changer les mots de passe via l'API ou pgAdmin
- Executer `python -m scripts.migrate_encrypt` pour chiffrer les noms/prenoms
- En production, envisager de supprimer les INSERT de test de `init.sql`

### 2. Perte de ENCRYPTION_KEY = donnees perdues

Si vous perdez la cle `ENCRYPTION_KEY`, **toutes les donnees chiffrees sont
irrecuperables**. Il n'y a pas de backdoor, pas de recuperation possible.

**Solutions** :
- Sauvegarder `.env` a 2+ endroits (VPS + local + cloud)
- Ne JAMAIS changer ENCRYPTION_KEY sans faire la procedure de rotation complete
- Documenter la cle dans un gestionnaire de mots de passe (Bitwarden, 1Password)

### 3. Dashboard Traefik expose

Le `docker-compose.yml` expose le port `8080` (dashboard Traefik).
En production, ce port ne doit PAS etre accessible depuis Internet.

**Solutions** :
```bash
# Option A : Firewall (UFW)
sudo ufw deny 8080

# Option B : Supprimer le port du docker-compose.yml
# Retirer la ligne "8080:8080" dans la section ports de traefik

# Option C : Desactiver le dashboard
# Retirer "--api.insecure=true" des commandes traefik
```

### 4. CORS trop permissif

En developpement, CORS accepte `localhost` et `192.168.*`. En production,
restreindre aux domaines reels.

**Solution** : Verifier la config CORS dans `app/main.py` et limiter les origines.

### 5. Docker socket monte en lecture seule

Traefik a besoin du socket Docker (`/var/run/docker.sock:ro`). C'est necessaire
mais c'est un vecteur d'attaque. Le `:ro` (lecture seule) limite le risque.

### 6. Volumes Docker = donnees persistantes

Les donnees PostgreSQL sont dans un volume Docker (`postgres_data`).
Si vous faites `docker compose down -v`, **les volumes sont supprimes**.

```bash
# SAFE — arrete les conteneurs, garde les donnees
docker compose down

# DANGEREUX — supprime TOUT y compris les donnees
docker compose down -v    # NE JAMAIS FAIRE EN PROD sans backup
```

---

## 12. Depannage

### L'API ne demarre pas

```bash
# Verifier les logs
docker compose logs api

# Causes frequentes :
# - DATABASE_URL incorrect dans .env
# - PostgreSQL pas encore pret (healthcheck)
# - ENCRYPTION_KEY manquante
```

### Certificat TLS non genere

```bash
# Verifier les logs Traefik
docker compose logs traefik | grep -i "acme\|certificate\|error"

# Causes frequentes :
# - DNS ne pointe pas encore vers le VPS
# - Port 80 bloque par le firewall (Let's Encrypt en a besoin)
# - Trop de tentatives (rate limit Let's Encrypt : 5/semaine par domaine)
```

### Donnees illisibles apres changement de cle

```bash
# Vous avez probablement change ENCRYPTION_KEY sans faire la migration
# Solution :
# 1. Remettre l'ANCIENNE ENCRYPTION_KEY dans .env
# 2. Redemarrer l'API
# 3. Suivre la procedure de rotation (section 6)
```

### PostgreSQL plein

```bash
# Verifier la taille
docker exec schooltrack_db psql -U schooltrack -d schooltrack \
  -c "SELECT pg_size_pretty(pg_database_size('schooltrack'));"

# Nettoyer les vieux audit_logs (plus de 1 an)
docker exec schooltrack_db psql -U schooltrack -d schooltrack \
  -c "DELETE FROM audit_logs WHERE performed_at < NOW() - INTERVAL '1 year';"

# VACUUM pour recuperer l'espace
docker exec schooltrack_db psql -U schooltrack -d schooltrack -c "VACUUM FULL;"
```

### Redemarrage complet (dernier recours)

```bash
docker compose down
docker compose up -d --build
docker compose ps
```

---

## Annexe : Architecture reseau en production

```
   Internet
      |
   Firewall VPS (ports 22, 80, 443 uniquement)
      |
   ┌──────────────────────────────────────────┐
   |  Traefik (ports 80 + 443)                |
   |  - Let's Encrypt auto                    |
   |  - HTTP -> HTTPS redirect                |
   |  - Reverse proxy                         |
   |                                          |
   |  ┌───────────────┐  ┌────────────────┐   |
   |  | api (8000)    |  | pgadmin (80)   |   |
   |  | FastAPI       |  | pgAdmin4       |   |
   |  | AES-256-GCM   |  |                |   |
   |  └───────┬───────┘  └────────────────┘   |
   |          |                               |
   |  ┌───────┴───────┐                       |
   |  | postgres      |                       |
   |  | (5432)        |                       |
   |  | Volume Docker |                       |
   |  └───────────────┘                       |
   └──────────────────────────────────────────┘
```

---

*Document genere le 7 mars 2026 -- SchoolTrack v4.2*
