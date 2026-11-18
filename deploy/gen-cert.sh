#!/usr/bin/env bash
# Génère un certificat TLS auto-signé pour la production du lab.
# Usage (depuis ~/taskflow-prod) : ./gen-cert.sh
# Produit : certs/taskflow.crt (certificat) et certs/taskflow.key (clé privée, 600)
set -euo pipefail

CERT_DIR="certs"
DAYS=365

# Git Bash (Windows) transforme les arguments qui commencent par "/" en chemins
# Windows ("/CN=..." deviendrait "C:/Program Files/Git/CN=..."). On désactive
# cette conversion. Sans effet sous Linux et macOS.
export MSYS_NO_PATHCONV=1

mkdir -p "$CERT_DIR"

# Ne pas écraser un certificat existant (le proxy l'utilise peut-être déjà).
if [ -s "$CERT_DIR/taskflow.crt" ] && [ -s "$CERT_DIR/taskflow.key" ]; then
  echo "Certificat déjà présent dans $CERT_DIR/ : rien à faire."
  exit 0
fi

openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout "$CERT_DIR/taskflow.key" \
  -out    "$CERT_DIR/taskflow.crt" \
  -days   "$DAYS" \
  -subj   "/CN=taskflow.localhost" \
  -addext "subjectAltName=DNS:taskflow.localhost,DNS:localhost,DNS:host.docker.internal,IP:127.0.0.1"

# La clé privée : lisible par son seul propriétaire. Le certificat : public.
chmod 600 "$CERT_DIR/taskflow.key"
chmod 644 "$CERT_DIR/taskflow.crt"

echo "Certificat généré :"
openssl x509 -in "$CERT_DIR/taskflow.crt" -noout -subject -enddate -ext subjectAltName