#!/usr/bin/env bash
# Prépare les variables TF_VAR_* pour les jobs OpenTofu (iac.yml, release.yml).
# Usage (dans infra/, APRÈS tofu init) :
#   ./ci-env.sh          -> garde la version DÉJÀ déployée (plan d'une PR, dérive)
#   ./ci-env.sh <tag>    -> déploie cette version (release, rollback)
# Écrit dans $GITHUB_ENV : les steps suivants du job voient ces variables.
set -euo pipefail

: "${STAGING_DIR:?STAGING_DIR absent (variable du conteneur runner)}"
: "${GITHUB_ENV:?à lancer dans un job GitHub Actions}"

owner="${GITHUB_REPOSITORY_OWNER,,}"      # ghcr.io exige des minuscules

# Version : celle demandée, sinon celle que le state connaît, sinon .deployed_tag.
tag="${1:-}"
if [ -z "$tag" ]; then
  tag="$(tofu output -raw image_tag 2>/dev/null || true)"
fi
if [ -z "$tag" ] && [ -s "$STAGING_DIR/.deployed_tag" ]; then
  tag="$(cat "$STAGING_DIR/.deployed_tag")"
fi
tag="${tag:-latest}"

# Le mot de passe qui a initialisé le volume (voir partie B).
password="$(sed -n 's/^POSTGRES_PASSWORD=//p' "$STAGING_DIR/.env" | tr -d '\r')"
if [ -z "$password" ]; then
  echo "::error::POSTGRES_PASSWORD introuvable dans $STAGING_DIR/.env"
  exit 1
fi
echo "::add-mask::$password"           # masqué dans TOUS les logs du job

{
  echo "TF_VAR_ghcr_owner=$owner"
  echo "TF_VAR_image_tag=$tag"
  echo "TF_VAR_db_password=$password"
} >> "$GITHUB_ENV"

echo "Variables OpenTofu prêtes : ghcr_owner=$owner, image_tag=$tag"
