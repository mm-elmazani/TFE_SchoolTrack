#!/bin/bash
# ============================================================================
# SchoolTrack — Restauration PostgreSQL depuis un backup
# Usage : ./scripts/restore_db.sh <fichier_backup.sql.gz>
# Exemple : ./scripts/restore_db.sh /backups/schooltrack/schooltrack_2026-04-19_020000.sql.gz
# ATTENTION : écrase toutes les données existantes.
# ============================================================================

set -euo pipefail

CONTAINER_NAME="schooltrack_db"
DB_NAME="schooltrack"
DB_USER="schooltrack"

# --- Vérification argument ---
if [ $# -ne 1 ]; then
    echo "Usage : $0 <fichier_backup.sql.gz>"
    echo "Exemple : $0 /backups/schooltrack/schooltrack_2026-04-19_020000.sql.gz"
    exit 1
fi

BACKUP_FILE="$1"

if [ ! -f "$BACKUP_FILE" ]; then
    echo "ERREUR : fichier introuvable : $BACKUP_FILE"
    exit 1
fi

echo "========================================"
echo "  RESTAURATION SCHOOLTRACK"
echo "  Fichier : $BACKUP_FILE"
echo "  Base    : $DB_NAME"
echo "========================================"
echo ""
echo "ATTENTION : toutes les données actuelles seront écrasées."
read -p "Confirmer la restauration ? (oui/non) : " CONFIRM

if [ "$CONFIRM" != "oui" ]; then
    echo "Restauration annulée."
    exit 0
fi

echo ""
echo "[$(date)] Arrêt de l'API pour éviter les connexions actives..."
docker stop schooltrack_api 2>/dev/null || true

echo "[$(date)] Suppression et recréation de la base de données..."
docker exec "$CONTAINER_NAME" psql -U "$DB_USER" -c "DROP DATABASE IF EXISTS ${DB_NAME};"
docker exec "$CONTAINER_NAME" psql -U "$DB_USER" -c "CREATE DATABASE ${DB_NAME} OWNER ${DB_USER};"

echo "[$(date)] Restauration en cours..."
gunzip -c "$BACKUP_FILE" | docker exec -i "$CONTAINER_NAME" psql -U "$DB_USER" -d "$DB_NAME"

echo "[$(date)] Redémarrage de l'API..."
docker start schooltrack_api 2>/dev/null || true

echo ""
echo "[$(date)] Restauration terminée avec succès."
echo "Vérifier les logs API : docker logs schooltrack_api --tail=50"
