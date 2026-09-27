#!/bin/sh
set -eu

# Sauvegarde nocturne (docs/03 §8, docs/04 J7) : pg_dump + rétention locale de
# 7 jours. Restauration : voir restore.sh.
BACKUP_DIR="${BACKUP_DIR:-/backups}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"
STAMP=$(date +%Y%m%d-%H%M%S)
FILE="$BACKUP_DIR/news-$STAMP.sql.gz"

mkdir -p "$BACKUP_DIR"
pg_dump "$DATABASE_URL" | gzip > "$FILE"
echo "sauvegarde écrite : $FILE"

find "$BACKUP_DIR" -name 'news-*.sql.gz' -mtime "+$RETENTION_DAYS" -delete
echo "rétention : fichiers de plus de $RETENTION_DAYS jours supprimés"

# ponytail: pas de copie hors site pour l'instant (règle 3-2-1, docs/03 §8) —
# aucune destination choisie ; ajouter un envoi rclone/restic ici une fois
# une destination décidée.
