# Déploiement de TaskFlow

## Environnements

| | dev | staging | production |
|---|---|---|---|
| Fichier | `compose.yaml` | `compose.staging.yaml` | `compose.prod.yaml` |
| Dossier | le dépôt | `~/taskflow-staging` | `~/taskflow-prod` |
| Images | construites localement | `ghcr.io/<owner>/taskflow-*:<sha>` | **les mêmes** que le staging |
| Accès | http://localhost:8080 | http://localhost:8081 | https://taskflow.localhost |
| HTTPS | non | non (écart assumé) | oui, proxy Nginx |

Règle : *build once, deploy many*. Une image est construite une fois par commit
(tag = SHA court), puis promue de staging à production. Seule la configuration
(le `.env` de chaque dossier) change.

## Ce qui va où

| Élément | Où | Dans Git ? |
|---|---|---|
| Code, fichiers compose, scripts, config Nginx | le dépôt | oui |
| Secrets (`.env`) | dossier de l'environnement, `chmod 600` | **jamais** (modèle : `.env.example`) |
| Certificat et clé (`certs/`) | dossier de l'environnement | **jamais** |
| Sauvegardes (`backups/`) | dossier de l'environnement | **jamais** |
| Version en ligne / précédente | `.deployed_tag`, `.previous_tag` | non (état du serveur) |

## Installer la production (une seule fois)

```bash
mkdir -p ~/taskflow-prod/nginx && cd ~/taskflow-prod
cp ~/taskflow/compose.prod.yaml ~/taskflow/deploy/*.sh .
cp ~/taskflow/deploy/nginx/taskflow.conf nginx/
cp ~/taskflow/.env.example .env && chmod 600 .env
PASS=$(openssl rand -hex 24) && sed -i "s/changez-moi/$PASS/g" .env && unset PASS
nano .env        # GHCR_OWNER en minuscules ; ports 8082/8443 si 80/443 sont pris
./gen-cert.sh
```

## Déployer, vérifier, revenir en arrière

```bash
./deploy.sh <sha>                                                  # déployer
CACERT=certs/taskflow.crt ./smoke-test.sh https://localhost/health <sha>   # vérifier
./deploy.sh "$(cat .previous_tag)"                                 # rollback
```

`deploy.sh` : valide le tag, télécharge les images (`pull` : rien n'est touché
si l'image manque), remplace les conteneurs et attend qu'ils soient sains
(`--wait`), recharge le proxy (`nginx -s reload`), puis mémorise les versions.

## Sauvegarder et restaurer

```bash
./backup.sh                                            # backups/taskflow-<date>.sql.gz
export IMAGE_TAG=$(cat .deployed_tag)                  # exigé par le fichier compose
gunzip -c backups/<fichier>.sql.gz \
  | docker compose -f compose.prod.yaml exec -T db psql -q -U taskflow -d taskflow
```

Une sauvegarde jamais restaurée n'est pas une sauvegarde. En production réelle :
règle 3-2-1 (3 copies, 2 supports, 1 hors site).

## En cas de problème

| Symptôme | Piste |
|---|---|
| `IMAGE_TAG manquant` | `export IMAGE_TAG=$(cat .deployed_tag)` avant les commandes `docker compose` |
| `password authentication failed` | mot de passe différent entre `DATABASE_URL` et `POSTGRES_PASSWORD`, ou ancien volume |
| Le proxy redémarre en boucle | `certs/` vide : relancer `./gen-cert.sh` |
| 502 après un déploiement | le proxy n'a pas été rechargé : `docker compose -f compose.prod.yaml exec proxy nginx -s reload` |
| `bash\r: No such file` (runner Linux) | fins de ligne Windows : voir `.gitattributes` |