# Sécurité de TaskFlow

## Les contrôles

| Contrôle | Outil | Quand | Ce qu'il protège | Bloquant ? |
|---|---|---|---|---|
| Secrets dans le code | gitleaks | à chaque commit (pre-commit) et chaque PR (`security.yml`, tout l'historique) | fuite de jetons, mots de passe, clés | oui |
| Dépendances npm (SCA) | `npm audit --audit-level=high` | chaque PR, push sur `main`, chaque semaine | failles connues des paquets, `api` et `front` | oui (high, critical) |
| Code source (SAST) | Semgrep, règles `p/javascript` et `p/nodejsscan` | chaque PR, push sur `main`, chaque semaine | injection SQL, XSS, erreurs de code dangereuses | oui |
| Application en marche (DAST) | ZAP baseline, scan passif | chaque PR, push sur `main`, chaque semaine | en-têtes de sécurité, fuites d'information | oui (WARN et FAIL) |
| Images Docker | Trivy | chaque release (`release.yml`), avant publication | failles du système et des paquets embarqués | oui (CRITICAL corrigeable) |
| Mises à jour | Dependabot | en continu | dépendances npm, actions GitHub, images de base | non (ouvre des PR) |
| Moindre privilège | `permissions` minimales, actions épinglées par SHA | tous les workflows | vol de jeton, action compromise (supply chain) | — |

Le passage **hebdomadaire** de `security.yml` détecte les failles publiées **après** le dernier changement de code.

## Les en-têtes HTTP (`front/nginx.conf`)

| En-tête | Valeur | Protège contre |
|---|---|---|
| `Content-Security-Policy` | `default-src 'self'` ... `frame-ancestors 'none'`, sans `'unsafe-inline'` | scripts injectés (XSS), chargements depuis d'autres sites |
| `X-Frame-Options` | `DENY` (doublé par `frame-ancestors 'none'`) | clickjacking |
| `X-Content-Type-Options` | `nosniff` | exécution d'un fichier sous un autre type |
| `Referrer-Policy` | `strict-origin-when-cross-origin` | fuite d'adresses complètes vers d'autres sites |
| `Permissions-Policy` | `camera=(), microphone=(), geolocation=()` | usage de ces fonctions par un script malveillant |
| `server_tokens off` | (en-tête `Server` sans version) | lecture directe de la version de Nginx |
| `proxy_hide_header X-Powered-By` | (en-tête retiré) | lecture directe de la technologie de l'API (Express) |

Le `Cache-Control` est calculé par un `map` au niveau `http` : `add_header` n'est **pas hérité**, et une `location`
qui en poserait un perdrait tous les en-têtes ci-dessus. Vérifié sur `/`, `/health` et `/assets/*.js`.

Masquer `Server` et `X-Powered-By` **ne corrige aucune faille** : cela oblige seulement un attaquant à chercher.
La vraie garantie sur la version de Nginx est le scan **Trivy** de l'image.

## Le registre des exceptions

Toute alerte ignorée est listée ici. **Aucune exception sans raison ni date de revue.**

| Quoi | Où | Pourquoi | Qui | Décidé le | À revoir le |
|---|---|---|---|---|---|
| ZAP 10049, Storable and Cacheable Content | `.zap/rules.tsv` | les fichiers `/assets/` ont un nom haché et **doivent** être mis en cache ; `index.html` est en `no-cache` | mainteneur | 2026-11-20 | 2027-05-20 |
| ZAP 10109, Modern Web Application | `.zap/rules.tsv` | simple information : le site est une application JavaScript | mainteneur | 2026-11-20 | 2027-05-20 |
| ZAP 90004, Cross-Origin-Embedder-Policy | `.zap/rules.tsv` | l'isolation entre origines n'est pas nécessaire ; l'en-tête pourrait bloquer des ressources légitimes | mainteneur | 2026-11-20 | 2027-05-20 |

## Les décisions sur les dépendances (2026-11-20)

| Alerte | Décision |
|---|---|
| `body-parser` < 1.20.9, **high**, en **production** (via Express) | **corrigée** : `npm audit fix`, compatible |
| Vitest 2.x, `tinypool`, `@vitest/mocker`, coverage-v8 : **critical** et moderate, **devDependencies** | **corrigées** : Vitest et coverage-v8 en **4.1.12**. Vitest 5 a été écarté : il exige Node 22, or la CI et l'image de production utilisent Node 20 |
| Vite ≤ 6.4.3 et `esbuild` (serveur de **développement**), moderate | **corrigées** : Vite **6.4.6** |

Résultat : `npm audit` ne signale plus aucune faille dans `api` ni dans `front`.

**Point ouvert : Node 20 est en fin de vie depuis avril 2026** et ne reçoit plus de correctifs de sécurité.
La migration vers Node 22 (images de l'API et du front, matrice de la CI) est suivie dans une issue dédiée.
Elle débloquera aussi le passage à Vitest 5.

## Les limites connues

- **ZAP baseline est passif** : il n'envoie aucune attaque. Il ne détecte pas une injection SQL ou une faille d'accès.
  Un scan **actif** (`zap-full-scan.py`, ou `zap-api-scan.py` sur les routes de l'API) devrait tourner sur un
  environnement dédié, jamais sur la production.
- **ZAP ne teste ni l'authentification ni les routes `POST`/`PATCH`/`DELETE`** de l'API : il explore seulement les
  pages qu'il trouve.
- **Le DAST scanne la stack de développement** (`compose.yaml`, en HTTP) : le proxy HTTPS de production, ses
  certificats et un éventuel en-tête HSTS ne sont pas testés.
- **Semgrep** n'utilise que des règles publiques : il ne connaît pas les règles métier de TaskFlow.
- **`npm audit` et Trivy** ne connaissent que les failles **déjà publiées**.
- **gitleaks** repère des formats de secrets connus : un mot de passe « ordinaire » écrit en clair peut lui échapper.
