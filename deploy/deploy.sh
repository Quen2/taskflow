#!/usr/bin/env bash
# Déploie une version de TaskFlow dans le dossier de l'environnement.
# Usage    : ./deploy.sh <tag>     (tag = SHA court : 7 caractères hexadécimaux)
# Rollback : ./deploy.sh "$(cat .previous_tag)"
# Mémoire  : .deployed_tag = version en ligne, .previous_tag = version d'avant
set -euo pipefail

TAG="${1:-}"

# 1. Valider l'entrée AVANT toute action (elle peut venir d'un workflow_dispatch).
if [[ ! "$TAG" =~ ^[0123456789abcdef]{7}$ ]]; then
  echo "Usage : $0 <sha court de 7 caractères hexadécimaux> (reçu : '$TAG')" >&2
  exit 2
fi

# Travailler dans le dossier du script, d'où qu'on le lance :
# c'est là que se trouvent le fichier compose, le .env, nginx/ et certs/.
cd "$(dirname "$0")"

# Chaque dossier d'environnement contient UN fichier compose : on le détecte.
if   [ -f compose.prod.yaml ];    then FICHIER=compose.prod.yaml
elif [ -f compose.staging.yaml ]; then FICHIER=compose.staging.yaml
else echo "Aucun fichier compose dans $(pwd)" >&2; exit 1
fi

compose() { docker compose -f "$FICHIER" "$@"; }

ACTUELLE=""
[ -f .deployed_tag ] && ACTUELLE="$(cat .deployed_tag)"
echo "==> Déploiement de $TAG avec $FICHIER (en ligne : ${ACTUELLE:-aucune})"

export IMAGE_TAG="$TAG"

# 2. Télécharger d'abord : si l'image n'existe pas, on s'arrête ICI,
#    sans avoir touché aux conteneurs qui tournent.
compose pull

# 3. Remplacer les conteneurs et attendre qu'ils soient tous "healthy".
compose up -d --wait --remove-orphans

# 4. Le proxy (prod seulement) a résolu "front" à son démarrage :
#    le front vient d'être recréé, on le force à relire son adresse.
if compose config --services | grep -qx proxy; then
  compose exec -T proxy nginx -t
  compose exec -T proxy nginx -s reload
fi

# 5. Mémoriser les versions (seulement maintenant : le déploiement a réussi).
if [ -n "$ACTUELLE" ] && [ "$ACTUELLE" != "$TAG" ]; then
  echo "$ACTUELLE" > .previous_tag
fi
echo "$TAG" > .deployed_tag

echo "==> $TAG en ligne (précédente : $(cat .previous_tag 2>/dev/null || echo aucune))"