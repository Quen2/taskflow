#!/usr/bin/env bash
# Sauvegarde la base PostgreSQL de l'environnement.
# Usage : ./backup.sh  ->  backups/taskflow-AAAAMMJJ-HHMMSS.sql.gz
# Restauration :
#   gunzip -c backups/<fichier>.sql.gz \
#     | docker compose -f compose.prod.yaml exec -T db psql -q -U taskflow -d taskflow
# GARDER (défaut 7) : nombre de sauvegardes conservées.
set -euo pipefail

cd "$(dirname "$0")"

if   [ -f compose.prod.yaml ];    then FICHIER=compose.prod.yaml
elif [ -f compose.staging.yaml ]; then FICHIER=compose.staging.yaml
else echo "Aucun fichier compose dans $(pwd)" >&2; exit 1
fi

# Le fichier compose exige IMAGE_TAG : on reprend la version en ligne.
if [ ! -s .deployed_tag ]; then
  echo "Pas de .deployed_tag : aucune version déployée ici ?" >&2
  exit 1
fi
export IMAGE_TAG="$(cat .deployed_tag)"

GARDER="${GARDER:-7}"
mkdir -p backups
chmod 700 backups

CIBLE="backups/taskflow-$(date +%Y%m%d-%H%M%S).sql.gz"
PARTIEL="$CIBLE.partiel"
trap 'rm -f "$PARTIEL"' EXIT     # en cas d'échec, pas de fichier à moitié écrit

# pg_dump tourne DANS le conteneur db, qui connaît déjà l'utilisateur et la base.
docker compose -f "$FICHIER" exec -T db \
  sh -c 'pg_dump --clean --if-exists -U "$POSTGRES_USER" -d "$POSTGRES_DB"' \
  | gzip > "$PARTIEL"

mv "$PARTIEL" "$CIBLE"
chmod 600 "$CIBLE"
echo "Sauvegarde : $CIBLE ($(du -h "$CIBLE" | cut -f1))"

# Rotation : ne garder que les GARDER plus récentes.
ls -1t backups/taskflow-*.sql.gz | tail -n +"$((GARDER + 1))" | xargs -r rm -f --