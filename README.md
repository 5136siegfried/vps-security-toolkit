# vps-security-toolkit

<div align="center">

**A modular DevSecOps audit toolkit for VPS infrastructures.**  
Generates a self-contained HTML report with a global security score.  
Run it manually, schedule it, or invoke it as a reusable CI workflow from any GitHub project.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Shell: Bash](https://img.shields.io/badge/Shell-Bash-green.svg)](run.sh)
[![CI: GitHub Actions](https://img.shields.io/badge/CI-GitHub_Actions-black.svg)](.github/workflows)

[English](#english) · [Français](#français)

</div>

---

## English

### What it does

Runs a comprehensive security audit on a Linux VPS and produces a single, self-contained HTML report — no external dependencies, no SaaS, no data leaving your infrastructure (unless you configure webhook/mail notifications).

The report includes a **global score /100** computed across all checks, with color-coded sections, collapsible panels, and direct remediation commands for every finding.

### Coverage

| Domain | What is checked |
|---|---|
| **System** | CPU, RAM, disk, inodes, swap, uptime, kernel, top processes |
| **Network** | Open ports, firewall rules (ufw/iptables/nftables), outbound connections to public IPs, ARP table, routes |
| **SSH & Access** | Bruteforce attempts, top attacker IPs, active sessions, `sshd_config` vs CIS benchmark (9 parameters) |
| **Users & Privileges** | Accounts with active shells, UID 0 non-root, sudo/wheel members, authorized SSH keys, sudoers, crontabs |
| **TLS Certificates** | Expiry check on Let's Encrypt certs with days remaining and color alert |
| **Kernel hardening** | 11 sysctl security parameters evaluated against recommended values |
| **Services** | Systemd failed units, running services, services enabled at boot |
| **Docker** | Container state/health/restarts, privileged mode, dangling images, log driver, stdout log error detection, Trivy image scan |
| **Nginx** | Access log parsing — injection/traversal patterns, known scanner User-Agents, 4xx/5xx rates, top attacker IPs, top endpoints |
| **Integrity** | Lynis CIS hardening index, rkhunter, chkrootkit, debsums, AIDE |
| **CVE** | Trivy system scan (HIGH/CRITICAL only) |
| **Secrets** | Credential pattern detection in config files (`.env`, `.yaml`, `.conf`, ...) — values masked in output |
| **Best practices** | 20 checks across 6 domains — see table below |

**Best practices checks (04-bestpractices.sh)**

| Domain | Checks |
|---|---|
| Security tools | fail2ban (installed + active + jails), lynis, rkhunter (db date), chkrootkit, debsums, aide (+ db initialized), trivy |
| System | unattended-upgrades (installed + enabled), NTP sync (timedatectl/chrony), swap configured, journald persistent storage, logrotate nginx |
| SSH | AllowUsers/AllowGroups defined, non-standard port |
| Docker | json-file log driver, userns-remap, containers without HEALTHCHECK, docker-bench-security |
| Backup | borg, restic, rclone, or rsync in cron |
| Network | IPv6 active without global address |

### Architecture

```
vps-security-toolkit/
│
├── run.sh                        # Single entry point — sources everything, builds HTML
│
├── lib/
│   ├── html.sh                   # Shared HTML rendering helpers (section, table, badge, alert...)
│   ├── score.sh                  # Global score engine — score_penalty <pts> "<reason>"
│   └── notify.sh                 # Webhook (Discord/Slack) + mail dispatch
│
├── collectors/
│   ├── 00-system.sh              # CPU, RAM, disk, processes, packages
│   ├── 01-network.sh             # Ports, firewall, connections, ARP, routes
│   ├── 02-auth.sh                # SSH, users, privileges, SUID/SGID
│   ├── 03-integrity.sh           # Lynis, rootkits, debsums, AIDE, Trivy, secrets, certs, services
│   ├── 04-bestpractices.sh       # 20 best practice checks with remediation commands
│   ├── 05-docker.sh              # Container state, image scan, stdout log analysis
│   └── 06-nginx-attacks.sh       # Nginx access log attack detection
│
├── Dockerfile                    # All-in-one image: lynis, trivy, rkhunter, chkrootkit, debsums, aide
├── docker-compose.yml
├── .env.example
│
└── .github/workflows/
    ├── audit.yml                 # Reusable workflow (workflow_call) — callable from any repo
    ├── scheduled.yml             # Weekly cron
    └── on-demand.yml             # Manual dispatch with host as input
```

### Quick start

**Prerequisites:** Linux host, bash, root access. Optional but recommended: `lynis`, `trivy`, `rkhunter`, `chkrootkit`, `debsums`, `aide`, `fail2ban` — missing tools are reported as warnings in the Best Practices section, not errors.

```bash
git clone https://github.com/5136siegfried/vps-security-toolkit.git
cd vps-security-toolkit
cp .env.example .env        # edit at minimum NGINX_LOG_PATHS
chmod +x run.sh lib/*.sh collectors/*.sh
sudo ./run.sh --output /tmp/audit.html
```

Retrieve the report from a remote VPS:
```bash
scp root@your-vps:/tmp/audit.html ./audit.html && open audit.html
```

### Nginx log configuration

The toolkit uses **explicit per-host path configuration** (no hardcoded convention). Set `NGINX_LOG_PATHS` in your `.env` or export it before running:

```bash
# Single site
NGINX_LOG_PATHS=/var/log/nginx/mysite.access.log

# Multi-site — comma-separated
NGINX_LOG_PATHS=/var/log/nginx/site1.access.log,/var/log/nginx/site2.access.log,/var/log/nginx/api.access.log
```

Fallback: if `NGINX_LOG_PATHS` is not set, the collector scans `/var/log/nginx/*access*.log` automatically.

### Configuration reference

| Variable | Default | Purpose |
|---|---|---|
| `NGINX_LOG_PATHS` | auto | Nginx access log paths, comma-separated |
| `NGINX_LOG_LINES` | `5000` | Lines analyzed per log file |
| `DOCKER_LOG_LINES` | `500` | Lines read per container |
| `NOTIFY_SCORE_THRESHOLD` | `70` | Score below which notification fires |
| `NOTIFY_WEBHOOK_URL` | — | Discord or Slack webhook URL |
| `NOTIFY_WEBHOOK_TYPE` | `discord` | `discord` or `slack` |
| `NOTIFY_MAIL_TO` | — | Mail recipient (requires `mail`/`sendmail`) |
| `NOTIFY_MAIL_FROM` | auto | Sender address |

### Reusable CI workflow

The core value of this toolkit in a multi-project context: **one workflow definition, invoked from any repository**.

```yaml
# In any other GitHub repo — .github/workflows/security.yml
name: VPS Security Audit

on:
  schedule:
    - cron: "0 6 * * 1"    # every Monday at 06:00 UTC
  workflow_dispatch: {}

jobs:
  audit:
    uses: 5136siegfried/vps-security-toolkit/.github/workflows/audit.yml@main
    with:
      target_host: ${{ vars.VPS_HOST }}
      nginx_log_paths: "/var/log/nginx/mysite.access.log"
      score_threshold: "70"
    secrets: inherit
```

**Required secrets** (set once in the calling repo's Settings → Secrets):

| Secret | Required | Purpose |
|---|---|---|
| `VPS_SSH_KEY` | ✅ | Private SSH key for the target host |
| `NOTIFY_WEBHOOK_URL` | optional | Discord/Slack notification |
| `NOTIFY_MAIL_TO` | optional | Email notification |

The workflow SSHes into the target, copies the toolkit, runs the audit, fetches the HTML report as a GitHub Actions artifact (retained 90 days), and cleans up after itself.

### Notifications

Notifications fire only when the score drops below the configured threshold — no noise on clean runs.

**Discord/Slack webhook:**
```bash
NOTIFY_WEBHOOK_URL=https://discord.com/api/webhooks/...
NOTIFY_WEBHOOK_TYPE=discord   # or slack
NOTIFY_SCORE_THRESHOLD=70
```

**Mail:**
```bash
NOTIFY_MAIL_TO=admin@example.com
# requires mail or sendmail available on the host
```

### Known limitations

- **Not a real-time IDS.** This is a point-in-time audit, not continuous intrusion detection. It does not replace fail2ban, OSSEC, or a SIEM.
- **Nginx format assumption.** The attack collector expects the standard combined log format. A custom log format requires adapting `collectors/06-nginx-attacks.sh`.
- **Docker logs are stdout only.** No aggregation or long-term retention. For high-volume or production-grade log analysis, a dedicated pipeline (Loki, ELK) is recommended alongside this toolkit.
- **Root required for full coverage.** Without root, rkhunter, debsums, AIDE, secrets scan, and SUID checks are degraded and flagged as such in the report.
- **Trivy rootfs scan is slow** (~5-10 min on a busy VPS). A `timeout` wrapper is applied; the scan may be incomplete on large filesystems.

---

## Français

### Ce que ça fait

Lance un audit de sécurité complet sur un VPS Linux et produit un rapport HTML autonome — aucune dépendance externe, aucun SaaS, aucune donnée quittant l'infrastructure (sauf notification webhook/mail si configurée).

Le rapport inclut un **score global /100** calculé sur l'ensemble des checks, avec des sections colorées, des panneaux repliables, et les commandes de remédiation directement dans chaque alerte.

### Usage rapide

```bash
git clone https://github.com/5136siegfried/vps-security-toolkit.git
cd vps-security-toolkit
cp .env.example .env
sudo ./run.sh --output /tmp/audit.html
```

Récupérer le rapport depuis un VPS distant :
```bash
scp root@mon-vps:/tmp/audit.html . && open audit.html
```

### Configuration Nginx (par hôte)

Le toolkit ne suppose aucune convention de chemin fixe. Définir `NGINX_LOG_PATHS` explicitement :

```bash
NGINX_LOG_PATHS=/var/log/nginx/site1.access.log,/var/log/nginx/site2.access.log
```

Si non défini : fallback automatique sur `/var/log/nginx/*access*.log`.

### Workflow CI réutilisable

```yaml
# Dans n'importe quel autre repo GitHub
jobs:
  audit:
    uses: 5136siegfried/vps-security-toolkit/.github/workflows/audit.yml@main
    with:
      target_host: ${{ vars.VPS_HOST }}
      nginx_log_paths: "/var/log/nginx/monsite.access.log"
    secrets: inherit
```

Le workflow se connecte en SSH sur la cible, copie le toolkit, lance l'audit, rapatrie le rapport en artifact CI (conservé 90 jours) et nettoie après lui.

### Contribuer

Voir [CONTRIBUTING.md](CONTRIBUTING.md) pour les règles de robustesse bash (`set -eu`, patterns `grep -c`, `find /`, SIGPIPE) et le processus de PR.

Licence MIT.

---

<div align="center">
<sub>Built for <a href="https://5136.fr">5136.fr</a> · No telemetry · No SaaS · Your data stays on your infrastructure</sub>
</div>
