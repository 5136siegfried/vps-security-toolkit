#!/usr/bin/env bash
# ================================================================
#  run.sh — Point d'entrée unique du vps-security-toolkit
#
#  Usage :
#    ./run.sh [--output /chemin/rapport.html] [--notify] [--report-url URL]
#
#  Variables d'environnement utiles :
#    NGINX_LOG_PATHS         chemins logs nginx, séparés par virgules
#    DOCKER_LOG_LINES        profondeur logs docker (défaut 500)
#    NGINX_LOG_LINES         profondeur logs nginx (défaut 5000)
#    NOTIFY_WEBHOOK_URL      webhook Discord/Slack
#    NOTIFY_WEBHOOK_TYPE     discord|slack (défaut discord)
#    NOTIFY_MAIL_TO          destinataire mail
#    NOTIFY_SCORE_THRESHOLD  seuil de notification (défaut 70)
#
#  Voir README.md pour le détail de configuration par hôte.
# ================================================================

set -eu
export LANG=C

TOOLKIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Arguments ────────────────────────────────────────────────
OUTPUT="./vps-audit-$(date +%Y%m%d-%H%M%S).html"
DO_NOTIFY=false
REPORT_URL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)     OUTPUT="$2"; shift 2 ;;
    --notify)     DO_NOTIFY=true; shift ;;
    --report-url) REPORT_URL="$2"; shift 2 ;;
    *) echo "Argument inconnu : $1" >&2; exit 1 ;;
  esac
done

HOSTNAME_VAL=$(hostname -f 2>/dev/null || hostname)
GENERATED_AT=$(date '+%Y-%m-%d %H:%M:%S %Z')
SCRIPT_START=$(date +%s)
IS_ROOT=false
[[ $EUID -eq 0 ]] && IS_ROOT=true

# ── Chargement des libs ──────────────────────────────────────
# shellcheck source=lib/html.sh
source "${TOOLKIT_ROOT}/lib/html.sh"
# shellcheck source=lib/score.sh
source "${TOOLKIT_ROOT}/lib/score.sh"
# shellcheck source=lib/notify.sh
source "${TOOLKIT_ROOT}/lib/notify.sh"

# ── Chargement des collectors ────────────────────────────────
for f in "${TOOLKIT_ROOT}"/collectors/*.sh; do
  # shellcheck source=/dev/null
  source "$f"
done

log "Démarrage — host=${HOSTNAME_VAL} root=${IS_ROOT}"
! $IS_ROOT && log "⚠ Pas root — certaines sections seront incomplètes"

# ── Collecte ─────────────────────────────────────────────────
collect_system
collect_cpu
collect_ram
collect_disk
collect_processes
collect_network
collect_network_advanced
collect_auth
collect_ssh_config
collect_users
collect_suid_sgid
collect_services
collect_certs
collect_kernel_params
collect_fail2ban
collect_lynis
collect_rkhunter
collect_chkrootkit
collect_debsums
collect_aide
collect_trivy_system
collect_secrets
collect_history
collect_docker
collect_docker_logs
collect_nginx_attacks
collect_bestpractices

score_finalize

SCRIPT_END=$(date +%s)
ELAPSED=$(( SCRIPT_END - SCRIPT_START ))
log "Collecte terminée en ${ELAPSED}s — score=${SCORE}/100"
log "Génération HTML..."

# ── Assemblage HTML ──────────────────────────────────────────
{
  echo "$HTML_HEAD"

  cat << EOF
<header class="report-header">
  <div class="logo">
    <span class="logo-icon">🛡</span>
    <div>
      <div style="font-family:var(--sans);font-size:17px;font-weight:700">VPS Security Report</div>
      <div class="host">${HOSTNAME_VAL}</div>
    </div>
  </div>
  <div class="meta">
    ${GENERATED_AT}<br>
    Kernel ${KERNEL} · ${ARCH} · ${PROC_COUNT} vCPU<br>
    Collecte : ${ELAPSED}s$(! $IS_ROOT && echo " · ⚠ non-root" || echo " · ✓ root")
  </div>
</header>
<div class="layout">
EOF

  echo "$HTML_NAV"

  render_score_section
  render_system_section
  render_cpu_section
  render_ram_section
  render_disk_section
  render_processes_section
  render_network_section
  render_network_advanced_section
  render_auth_section
  render_sshcfg_section
  render_users_section
  render_certs_section
  render_services_section
  render_cron_section
  render_docker_section
  render_nginx_section
  render_bestpractices_section
  render_kernel_section
  render_fail2ban_section
  render_lynis_section
  render_rootkits_section
  render_integrity_section
  render_suid_section
  render_secrets_section
  render_trivy_section
  render_pkgs_section
  render_history_section

  echo "$HTML_FOOT"
} > "$OUTPUT"

log "✓ Rapport généré : ${OUTPUT}"

# ── Notification ─────────────────────────────────────────────
if $DO_NOTIFY; then
  notify_dispatch "$SCORE" "$HOSTNAME_VAL" "$REPORT_URL" "${SCORE_ISSUES[@]}"
fi

echo "$OUTPUT"
