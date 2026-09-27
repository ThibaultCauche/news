# pg_dump/psql de la même version que postgres:16 (docs/03 §8) + crond de
# busybox, déjà présent dans l'image alpine, pour le déclenchement nocturne.
FROM postgres:16-alpine

COPY backup.sh /usr/local/bin/backup.sh
COPY restore.sh /usr/local/bin/restore.sh
COPY crontab /etc/crontabs/root
RUN chmod +x /usr/local/bin/backup.sh /usr/local/bin/restore.sh

CMD ["crond", "-f", "-l", "2"]
