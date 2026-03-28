#!/bin/bash
# ============================================================================
# SchoolTrack — Backup PostgreSQL quotidien
# Usage : ./scripts/backup.sh
# Cron  : 0 2 * * * /opt/schooltrack/scripts/backup.sh >> /var/log/schooltrack-backup.log 2>&1
# ============================================================================

set -euo pipefail

# --- Configuration ---
BACKUP_DIR="/backups/schooltrack"
CONTAINER_NAME="schooltrack_db"
RETENTION_DAYS=30
DATE=$(date +%Y-%m-%d_%H%M%S)
FILENAME="schooltrack_${DATE}.sql.gz"

# --- Creation du dossier si inexistant ---
mkdir -p "$BACKUP_DIR"

# --- Dump compresse ---
echo "[$(date)] Demarrage backup PostgreSQL..."

docker exec "$CONTAINER_NAME" pg_dump \
    -U schooltrack \
    -d schooltrack \
    --no-owner \
    --no-privileges \
    | gzip > "${BACKUP_DIR}/${FILENAME}"

# --- Verification ---
FILESIZE=$(stat -c%s "${BACKUP_DIR}/${FILENAME}" 2>/dev/null || echo "0")

if [ "$FILESIZE" -lt 1000 ]; then
    echo "[$(date)] ERREUR : backup trop petit (${FILESIZE} octets) — potentiel echec"
    exit 1
fi

echo "[$(date)] Backup OK : ${FILENAME} (${FILESIZE} octets)"

# --- Rotation : supprime les backups > 30 jours ---
DELETED=$(find "$BACKUP_DIR" -name "schooltrack_*.sql.gz" -mtime +${RETENTION_DAYS} -delete -print | wc -l)

if [ "$DELETED" -gt 0 ]; then
    echo "[$(date)] Rotation : ${DELETED} ancien(s) backup(s) supprime(s)"
fi

echo "[$(date)] Backup termine."
