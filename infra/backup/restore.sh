#!/bin/sh
set -eu

# Restauration manuelle : docker compose exec backup restore.sh /backups/news-<date>.sql.gz
# À tester une fois par mois (docs/03 §8, critère d'acceptation J7).
FILE="${1:?Usage: restore.sh <fichier.sql.gz>}"
echo "Restauration de $FILE dans $DATABASE_URL"
gunzip -c "$FILE" | psql "$DATABASE_URL"
echo "restauration terminée"
