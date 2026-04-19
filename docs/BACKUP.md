# Sauvegarde et restauration PostgreSQL — SchoolTrack

## Vue d'ensemble

- **Fréquence** : quotidienne à 2h du matin (Europe/Brussels)
- **Rétention** : 30 jours glissants (rotation automatique)
- **Stockage** : `/backups/schooltrack/` sur le VPS
- **Format** : `schooltrack_YYYY-MM-DD_HHMMSS.sql.gz` (dump compressé gzip)

---

## 1. Installation du cron sur le VPS

Se connecter en SSH puis exécuter :

```bash
# Rendre le script exécutable
chmod +x /opt/schooltrack/scripts/backup.sh
chmod +x /opt/schooltrack/scripts/restore_db.sh

# Créer le dossier de backups
mkdir -p /backups/schooltrack

# Créer le fichier de log
touch /var/log/schooltrack-backup.log

# Ajouter le cron (exécute backup.sh chaque nuit à 2h)
crontab -e
```

Ajouter la ligne suivante :

```
0 2 * * * /opt/schooltrack/scripts/backup.sh >> /var/log/schooltrack-backup.log 2>&1
```

Vérifier que le cron est actif :

```bash
crontab -l
```

---

## 2. Tester le backup manuellement

```bash
/opt/schooltrack/scripts/backup.sh
```

Vérifier que le fichier a bien été créé :

```bash
ls -lh /backups/schooltrack/
```

Vérifier les logs :

```bash
cat /var/log/schooltrack-backup.log
```

---

## 3. Restauration depuis un backup

> **ATTENTION** : la restauration écrase toutes les données existantes en base.
> Toujours tester sur un environnement de dev avant de restaurer en prod.

```bash
# Lister les backups disponibles
ls -lht /backups/schooltrack/

# Lancer la restauration (remplacer le nom du fichier)
/opt/schooltrack/scripts/restore_db.sh /backups/schooltrack/schooltrack_2026-04-19_020000.sql.gz
```

Le script :
1. Demande une confirmation explicite (`oui`)
2. Arrête l'API pour couper les connexions actives
3. Supprime et recrée la base de données
4. Importe le dump
5. Redémarre l'API

Après restauration, vérifier :

```bash
docker logs schooltrack_api --tail=50
curl https://api.schooltrack.yourschool.be/api/health
```

---

## 4. Vérification de l'état des backups

```bash
# Nombre de backups présents
ls /backups/schooltrack/ | wc -l

# Taille totale occupée
du -sh /backups/schooltrack/

# Dernier backup
ls -lt /backups/schooltrack/ | head -2
```

---

## 5. Restauration manuelle sans script (urgence)

Si le script de restauration est indisponible :

```bash
# Arrêter l'API
docker stop schooltrack_api

# Recréer la base
docker exec schooltrack_db psql -U schooltrack -c "DROP DATABASE IF EXISTS schooltrack;"
docker exec schooltrack_db psql -U schooltrack -c "CREATE DATABASE schooltrack OWNER schooltrack;"

# Restaurer
gunzip -c /backups/schooltrack/<fichier>.sql.gz | docker exec -i schooltrack_db psql -U schooltrack -d schooltrack

# Redémarrer l'API
docker start schooltrack_api
```
