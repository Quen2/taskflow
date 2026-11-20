# Incidents et runbooks : TaskFlow

## Runbooks

Les alertes de `monitoring/prometheus/rules/taskflow.yml` pointent vers ces procédures.

### Runbook TaskFlowApiDown

La sonde `/health`, qui passe par le front comme un utilisateur, échoue depuis plus d'une minute.

1. **Conteneurs** : dans `~/taskflow-prod`, `export IMAGE_TAG=$(cat .deployed_tag)` puis
   `docker compose -f compose.prod.yaml ps`. Quel service n'est pas `healthy` ?
2. **Version** : Grafana, panneau « Version en ligne ». Si elle n'a **pas** changé, un rollback ne servira à rien :
   la cause est dans la configuration ou l'environnement, pas dans l'image.
3. **Logs** : `docker compose -f compose.prod.yaml logs --no-log-prefix --since 15m api | jq -c 'select(.level != "info")'`.
4. **Configuration réellement reçue** (fonctionne même si le conteneur redémarre en boucle) :
   `docker inspect taskflow-prod-api-1 --format '{{range .Config.Env}}{{println .}}{{end}}' | sed 's/:[^:@]*@/:***@/'`.
5. Corriger **la cause**, recréer le service (`up -d --no-deps --force-recreate --wait api`), puis vérifier `/health`,
   une création de tâche, Grafana au vert et le mail `[RESOLVED]`.

### Runbook TaskFlowMetricsUnreachable

Prometheus ne lit plus `api:3000/metrics`. Si `TaskFlowApiDown` est aussi active, suivre son runbook : cette alerte
n'en est que la conséquence (elle est inhibée par Alertmanager). Sinon, vérifier que Prometheus est bien sur le
réseau `taskflow-prod`.

### Runbook TaskFlowHighErrorRate

Plus de 5 % de réponses 5xx pendant 5 minutes. Chercher les erreurs dans les logs
(`jq -c 'select(.status >= 500)'`), et vérifier si une nouvelle version vient d'être déployée : si oui, un rollback
par `workflow_dispatch` est la première action.

---

## Post-mortem : API indisponible le 2026-11-20 (DATABASE_URL invalide)

| | |
|---|---|
| **Date** | 2026-11-20 |
| **Durée** | environ 4 minutes (14h48 à 14h52, heure de Paris) |
| **Gravité** | critique : application inutilisable |
| **Statut** | résolu |

### Résumé

Après une modification de la configuration de production, la variable `DATABASE_URL` désignait un serveur de base
de données inexistant (`base-introuvable` au lieu de `db`). L'API ne pouvait plus se connecter à PostgreSQL au
démarrage et redémarrait en boucle.

**Impact utilisateur** : pendant environ 4 minutes, toutes les pages et tous les appels à l'API ont répondu
`502 Bad Gateway`. Aucune donnée n'a été perdue : la base de données n'a pas été touchée.

### Chronologie (heure de Paris)

| Heure | Événement |
|---|---|
| 14:46 | Une première modification du `.env` (variable `DATABASE_URL` renommée) est **refusée** par Compose (`DATABASE_URL manquant dans .env`) : aucun impact. Configuration restaurée. |
| 14:48 (à préciser) | Seconde modification : `DATABASE_URL` pointe vers `base-introuvable`. L'API est recréée. |
| 14:48:16 | Premier log `fatal` de l'API : `Démarrage impossible : Connection terminated due to connection timeout`. Début de l'impact. |
| ~14:48 | Grafana : « Disponibilité » passe à EN PANNE. Prometheus : `TaskFlowApiDown` en *pending*. |
| 14:49 (à préciser) | **Premier signal** : mail `TaskFlowApiDown` reçu (Mailpit). |
| 14:50 | Diagnostic : `502` côté utilisateur, `api` en `Restarting`, logs `fatal`, `diff` de la configuration. |
| 14:52 | Correction de `DATABASE_URL`, API recréée et `healthy`. Création de tâche OK. Fin de l'impact. |
| (à préciser) | Mail `[RESOLVED]` reçu. |

**Temps de détection** : environ 1 min 30 (de 14:48:16 à la réception du mail).
**Temps de rétablissement (MTTR)** : environ 4 minutes.

### Comment la supervision a aidé

- La **sonde blackbox** (boîte noire) a détecté la panne alors que l'API, arrêtée, ne publiait plus aucune métrique.
- Le **mail** contenait le résumé, l'adresse sondée et le lien vers ce runbook.
- Le panneau **« Version en ligne »** montrait une version inchangée : la cause n'était pas le code, un rollback était
  donc inutile.
- L'**inhibition** d'Alertmanager n'a envoyé qu'une alerte (`TaskFlowApiDown`), et masqué sa conséquence
  (`TaskFlowMetricsUnreachable`).
- Le **message de log** de l'API (`hint : Vérifiez DATABASE_URL`) désignait directement la bonne piste.

### Les 5 pourquoi

1. **Pourquoi les utilisateurs voyaient-ils une erreur 502 ?** Le front ne joignait plus l'API.
2. **Pourquoi le front ne joignait-il plus l'API ?** L'API redémarrait en boucle.
3. **Pourquoi l'API redémarrait-elle en boucle ?** Elle ne pouvait pas se connecter à PostgreSQL au démarrage.
4. **Pourquoi ne pouvait-elle pas s'y connecter ?** `DATABASE_URL` désignait un serveur qui n'existe pas.
5. **Pourquoi cette valeur a-t-elle atteint la production ?** Le `.env` de production a été modifié à la main, hors du
   pipeline, et rien ne vérifie la configuration avant de recréer un service.

### Ce qui a bien fonctionné

- Le `:?` de `compose.prod.yaml` a **bloqué** la première modification (variable absente) avant tout impact.
- L'alerte est arrivée en moins de 2 minutes, et le diagnostic a pris moins de 3 minutes.
- La base de données et ses données n'ont jamais été affectées.

### Ce qui a mal fonctionné

- Le `:?` vérifie que la variable **existe**, pas qu'elle est **correcte** : une valeur fausse passe.
- Les liens du mail (`http://<conteneur>:9093`) pointent vers des noms internes à Docker : ils ne s'ouvrent pas.
- Le panneau « Erreurs 5xx » restait presque vide : les 502 sont produits par Nginx, que rien ne mesure.
- `docker compose exec` est impossible sur un conteneur qui redémarre en boucle : il a fallu `docker inspect`.
- La copie `.env.bak` contenait le mot de passe de production.

### Actions

| # | Action | Type | Statut |
|---|---|---|---|
| 1 | L'API refuse de démarrer en production si `DATABASE_URL` est absente ou vide, avec un test dans `tests/config.test.js` | prévenir | issue #<N> |
| 2 | `deploy.sh` vérifie que le `.env` contient toutes les variables de `.env.example` avant de recréer un service | prévenir | à planifier |
| 3 | Modifier la configuration de production uniquement par une procédure tracée (PR ou script), jamais à la main | prévenir | à planifier |
| 4 | Ajouter `--web.external-url` à Prometheus et Alertmanager pour que les liens des mails fonctionnent | réagir plus vite | à planifier |
| 5 | Ajouter au tableau de bord un panneau sur le code HTTP de la sonde (`probe_http_status_code`), pour voir les 502 | détecter | à planifier |
