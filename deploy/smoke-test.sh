#!/usr/bin/env bash
# Smoke test : la version qu'on vient de déployer répond-elle vraiment ?
# Usage : ./smoke-test.sh <url de /health> [version attendue]
#   ex. : CACERT=certs/taskflow.crt ./smoke-test.sh https://localhost/health a1b2c3d
# Vérifie : status = ok, db = up, et version = version attendue (si fournie).
# CACERT (facultatif) : certificat à utiliser pour VÉRIFIER le HTTPS (jamais -k).
set -euo pipefail

URL="${1:?Usage : $0 <url de /health> [version attendue]}"
ATTENDUE="${2:-}"
TENTATIVES="${TENTATIVES:-10}"
PAUSE="${PAUSE:-3}"

OPTIONS_CURL=(-fsS --max-time 5)
if [ -n "${CACERT:-}" ]; then
  OPTIONS_CURL+=(--cacert "$CACERT")
fi

for i in $(seq 1 "$TENTATIVES"); do
  if REPONSE="$(curl "${OPTIONS_CURL[@]}" "$URL" 2>&1)"; then
    if grep -q '"status":"ok"' <<<"$REPONSE" \
       && grep -q '"db":"up"' <<<"$REPONSE" \
       && { [ -z "$ATTENDUE" ] || grep -q "\"version\":\"$ATTENDUE\"" <<<"$REPONSE"; }
    then
      echo "OK (tentative $i/$TENTATIVES) : $REPONSE"
      exit 0
    fi
  fi
  echo "Tentative $i/$TENTATIVES : pas encore bon -> $REPONSE" >&2
  sleep "$PAUSE"
done

echo "ÉCHEC : $URL ne répond pas comme attendu (version attendue : ${ATTENDUE:-non vérifiée})" >&2
exit 1