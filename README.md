# vps-security-toolkit

Trousse à outils d'audit et de surveillance DevSecOps pour infrastructures VPS — invocable en local, en conteneur, ou en CI réutilisable depuis n'importe quel projet GitHub.

## Ce que ça couvre

- **Système** — CPU, RAM, disque, inodes, top processus, ports ouverts
- **Réseau** — firewall, connexions sortantes suspectes, ARP, routes
- **Accès** — bruteforce SSH, conformité `sshd_config`, utilisateurs/sudoers, clés SSH
- **Intégrité** — Lynis (CIS), rkhunter + chkrootkit (rootkits), debsums + AIDE (intégrité fichiers)
- **Vulnérabilités** — Trivy (CVE système + images Docker)
- **Secrets** — détection de credentials exposés dans les configs (valeurs masquées)
- **Docker** — containers, images dangling, mode privileged, **logs applicatifs stdout** (erreurs, crash-loops)
- **Web (Nginx)** — **parsing des access logs** : injections/path traversal, scanners connus, taux 4xx/5xx, top IPs
- **Score global** — note /100 calculée sur l'ensemble des checks, avec liste des points faibles

## Structure

```
vps-security-toolkit/
├── run.sh                      # point d'entrée unique
├── lib/
│   ├── html.sh                 # helpers de rendu HTML
│   ├── score.sh                # calcul du score global
│   └── notify.sh               # webhook (Discord/Slack) + mail
├── collectors/
│   ├── 00-system.sh
│   ├── 01-network.sh
│   ├── 02-auth.sh
│   ├── 03-integrity.sh
│   ├── 05-docker.sh            # état + logs containers
│   └── 06-nginx-attacks.sh     # parsing access logs
├── Dockerfile                  # image "valise" avec tous les outils préinstallés
├── docker-compose.yml
├── .env.example
└── .github/workflows/
    ├── audit.yml                # workflow réutilisable (workflow_call)
    ├── scheduled.yml            # cron hebdo sur ce repo
    └── on-demand.yml            # déclenchement manuel avec host en paramètre
```

## Usage en local

```bash
sudo ./run.sh --output ./rapport.html
open rapport.html
```

## Usage en conteneur ("valise")

Aucune dépendance à installer sur l'hôte cible — tout est dans l'image.

```bash
cp .env.example .env   # adapter NGINX_LOG_PATHS etc.
docker compose run --rm audit
# rapport dans ./out/vps-audit.html
```

## Configuration des logs Nginx (par hôte)

Le toolkit ne suppose aucune convention de chemin fixe. Définir `NGINX_LOG_PATHS` par hôte :

```bash
export NGINX_LOG_PATHS="/var/log/nginx/site1.access.log,/var/log/nginx/site2.access.log"
```

Si non défini, fallback automatique sur `/var/log/nginx/*access*.log`.

## Invocation depuis un autre projet GitHub

Ce repo expose un **workflow réutilisable**. Dans n'importe quel autre repo :

```yaml
# .github/workflows/security.yml
name: Audit sécurité VPS

on:
  workflow_dispatch: {}

jobs:
  security-audit:
    uses: <ton-user>/vps-security-toolkit/.github/workflows/audit.yml@main
    with:
      target_host: ${{ vars.VPS_HOST }}
      nginx_log_paths: "/var/log/nginx/monsite.access.log"
    secrets: inherit
```

Secrets requis côté repo appelant : `VPS_SSH_KEY` (clé privée), et optionnellement `NOTIFY_WEBHOOK_URL` / `NOTIFY_MAIL_TO`.

## Notifications

Configurables via variables d'environnement ou secrets CI :

| Variable | Rôle |
|---|---|
| `NOTIFY_WEBHOOK_URL` | URL webhook Discord ou Slack |
| `NOTIFY_WEBHOOK_TYPE` | `discord` (défaut) ou `slack` |
| `NOTIFY_MAIL_TO` | destinataire mail (nécessite `mail` ou `sendmail` disponible) |
| `NOTIFY_SCORE_THRESHOLD` | score sous lequel la notification se déclenche (défaut 70) |

La notification ne part que si le score descend sous le seuil — pas de bruit à chaque run vert.

## Bonnes pratiques recommandées (non bloquantes)

- Passer les containers Docker en **driver `json-file`** explicite (déjà le défaut le plus souvent, le rapport indique ceux qui ne le sont pas) pour fiabiliser le parsing des logs dans le temps.
- Installer `lynis`, `trivy`, `rkhunter`, `chkrootkit`, `debsums`, `aide`, `fail2ban` sur l'hôte si vous lancez `run.sh` directement (sinon utiliser le mode conteneur qui les embarque déjà).
- Lancer en `sudo` pour un score fiable — sans root plusieurs checks (rkhunter, debsums, secrets, historique) sont dégradés et signalés comme tels dans le rapport.

## Limites connues

- Le parsing Nginx suppose le format de log **combiné** standard. Un format custom nécessitera d'adapter `collectors/06-nginx-attacks.sh`.
- Les logs Docker sont lus via `docker logs --tail N` (stdout) — pas d'agrégation centralisée. Pour un volume important ou de la rétention longue, un vrai pipeline de logs (Loki, ELK) reste recommandé en complément.
- Ce toolkit est un audit d'état, pas un EDR/IDS temps réel. Il ne remplace pas une détection d'intrusion continue.
