#!/usr/bin/env bash
# ================================================================
#  collectors/04-bestpractices.sh — Vérification des bonnes
#  pratiques et outils recommandés.
#  Source : doit être sourcé après lib/html.sh et lib/score.sh
# ================================================================

collect_bestpractices() {
  log "Bonnes pratiques..."
  BP_RESULTS=()
  # bp_check <id> <label> <status: ok|warn|fail> <detail>
  bp_check() { BP_RESULTS+=("${1}|${2}|${3}|${4}"); }

  # ── Outils de sécurité ──────────────────────────────────────
  cmd_exists fail2ban-client \
    && systemctl is-active fail2ban &>/dev/null \
    && bp_check "fail2ban"    "fail2ban installé et actif"              ok   "Jails actives : $(fail2ban-client status 2>/dev/null | grep 'Jail list' | cut -d: -f2 | xargs || echo '?')" \
    || { cmd_exists fail2ban-client \
      && bp_check "fail2ban"  "fail2ban installé mais inactif"          warn "systemctl start fail2ban" \
      || bp_check "fail2ban"  "fail2ban absent"                         fail "apt install fail2ban"; }

  cmd_exists lynis \
    && bp_check "lynis"       "lynis présent"                           ok   "$(lynis --version 2>/dev/null | head -1 || echo '')" \
    || bp_check "lynis"       "lynis absent"                            fail "apt install lynis"

  cmd_exists rkhunter && {
    db_date=$(rkhunter --propupd --dry-run 2>/dev/null | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1 || echo "?")
    bp_check "rkhunter"       "rkhunter présent"                        ok   "Base : ${db_date}"
  } || bp_check "rkhunter"    "rkhunter absent"                         fail "apt install rkhunter"

  cmd_exists chkrootkit \
    && bp_check "chkrootkit"  "chkrootkit présent"                      ok   "" \
    || bp_check "chkrootkit"  "chkrootkit absent"                       warn "apt install chkrootkit"

  cmd_exists debsums \
    && bp_check "debsums"     "debsums présent"                         ok   "" \
    || bp_check "debsums"     "debsums absent"                          warn "apt install debsums"

  cmd_exists aide && {
    [[ -f /var/lib/aide/aide.db ]] \
      && bp_check "aide"      "aide présent + base initialisée"         ok   "/var/lib/aide/aide.db" \
      || bp_check "aide"      "aide présent mais base non initialisée"  warn "aide --init && mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db"
  } || bp_check "aide"        "aide absent"                             warn "apt install aide"

  cmd_exists trivy \
    && bp_check "trivy"       "trivy présent"                           ok   "$(trivy --version 2>/dev/null | head -1 || echo '')" \
    || bp_check "trivy"       "trivy absent"                            warn "curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin"

  # ── Mises à jour automatiques ────────────────────────────────
  cmd_exists unattended-upgrade && {
    systemctl is-enabled unattended-upgrades &>/dev/null \
      && bp_check "unattended" "unattended-upgrades actif"              ok   "Mises à jour sécurité automatiques" \
      || bp_check "unattended" "unattended-upgrades installé mais désactivé" warn "systemctl enable --now unattended-upgrades"
  } || bp_check "unattended"   "unattended-upgrades absent"             fail "apt install unattended-upgrades && dpkg-reconfigure -plow unattended-upgrades"

  # ── NTP ──────────────────────────────────────────────────────
  if cmd_exists timedatectl; then
    timedatectl status 2>/dev/null | grep -q 'synchronized: yes' \
      && bp_check "ntp"       "Horloge synchronisée (NTP)"             ok   "$(timedatectl show -p NTPService --value 2>/dev/null || echo 'systemd-timesyncd')" \
      || bp_check "ntp"       "NTP non synchronisé"                    warn "timedatectl set-ntp true"
  elif cmd_exists chronyc; then
    chronyc tracking 2>/dev/null | grep -q 'Reference ID' \
      && bp_check "ntp"       "Horloge synchronisée (chrony)"          ok   "" \
      || bp_check "ntp"       "chrony présent mais non synchronisé"    warn "systemctl restart chronyd"
  else
    bp_check "ntp"            "Aucun service NTP détecté"               warn "apt install systemd-timesyncd"
  fi

  # ── Swap ─────────────────────────────────────────────────────
  local swap_total
  swap_total=$(awk '/^SwapTotal/{print $2}' /proc/meminfo)
  [[ "$swap_total" -gt 0 ]] \
    && bp_check "swap"        "Swap configuré"                          ok   "$(( swap_total / 1024 )) MB" \
    || bp_check "swap"        "Aucun swap configuré"                    warn "Risque OOM killer — fallocate -l 2G /swapfile && mkswap /swapfile && swapon /swapfile"

  # ── Journald persistant ──────────────────────────────────────
  local journald_storage
  journald_storage=$(grep -iE '^Storage' /etc/systemd/journald.conf 2>/dev/null | cut -d= -f2 | xargs || echo "auto")
  [[ "$journald_storage" == "persistent" ]] \
    && bp_check "journald"    "Journald : logs persistants"             ok   "Storage=persistent" \
    || bp_check "journald"    "Journald : logs non persistants (Storage=${journald_storage})" warn "Ajouter Storage=persistent dans /etc/systemd/journald.conf"

  # ── Logrotate nginx ──────────────────────────────────────────
  [[ -f /etc/logrotate.d/nginx ]] \
    && bp_check "logrotate"   "Logrotate nginx configuré"               ok   "/etc/logrotate.d/nginx" \
    || bp_check "logrotate"   "Logrotate nginx absent"                  warn "Créer /etc/logrotate.d/nginx"

  # ── SSH hardening ────────────────────────────────────────────
  local ssh_cfg="/etc/ssh/sshd_config"
  if [[ -f "$ssh_cfg" ]]; then
    # AllowUsers ou AllowGroups
    grep -qiE '^(AllowUsers|AllowGroups)\s' "$ssh_cfg" 2>/dev/null \
      && bp_check "ssh_allow"  "SSH AllowUsers/AllowGroups défini"     ok   "$(grep -iE '^(AllowUsers|AllowGroups)\s' "$ssh_cfg" | head -1)" \
      || bp_check "ssh_allow"  "SSH sans restriction AllowUsers/AllowGroups" warn "Ajouter AllowUsers <user> dans sshd_config"
    # Port non standard
    local ssh_port
    ssh_port=$(grep -iE '^Port\s' "$ssh_cfg" 2>/dev/null | awk '{print $2}' | head -1 || echo "22")
    [[ "$ssh_port" != "22" && -n "$ssh_port" ]] \
      && bp_check "ssh_port"   "SSH sur port non standard (${ssh_port})" ok  "" \
      || bp_check "ssh_port"   "SSH sur port 22 (port standard)"         warn "Optionnel : changer le port dans sshd_config réduit le bruit bruteforce"
  fi

  # ── Docker bonnes pratiques ──────────────────────────────────
  if cmd_exists docker && docker info &>/dev/null 2>&1; then
    # Log driver dans daemon.json
    local log_driver
    log_driver=$(docker info --format '{{.LoggingDriver}}' 2>/dev/null || echo "?")
    [[ "$log_driver" == "json-file" ]] \
      && bp_check "docker_log" "Docker log driver : json-file"          ok   "" \
      || bp_check "docker_log" "Docker log driver : ${log_driver}"      warn "Définir log-driver json-file dans /etc/docker/daemon.json"

    # userns-remap
    docker info 2>/dev/null | grep -q 'userns' \
      && bp_check "docker_userns" "Docker userns-remap activé"          ok   "" \
      || bp_check "docker_userns" "Docker userns-remap désactivé"       warn "Isolation renforcée : ajouter userns-remap dans /etc/docker/daemon.json"

    # Containers sans healthcheck
    local no_health
    no_health=$(docker ps -q 2>/dev/null | xargs -I{} docker inspect {} \
      --format '{{.Name}} health={{if .Config.Healthcheck}}{{if .Config.Healthcheck.Test}}ok{{else}}none{{end}}{{else}}none{{end}}' 2>/dev/null \
      | { grep -c 'health=none' || true; })
    [[ "$no_health" -eq 0 ]] \
      && bp_check "docker_health" "Tous les containers ont un healthcheck" ok "" \
      || bp_check "docker_health" "${no_health} container(s) sans HEALTHCHECK" warn "Ajouter HEALTHCHECK dans les Dockerfiles concernés"

    # docker bench (outil CIS)
    cmd_exists docker-bench-security \
      && bp_check "docker_bench" "docker-bench-security présent"        ok   "" \
      || bp_check "docker_bench" "docker-bench-security absent"         warn "https://github.com/docker/docker-bench-security"
  fi

  # ── Backup ───────────────────────────────────────────────────
  local backup_tool=""
  cmd_exists borg    && backup_tool="borgbackup"
  cmd_exists restic  && backup_tool="restic"
  cmd_exists rclone  && backup_tool="${backup_tool:+$backup_tool + }rclone"
  # rsync en cron
  crontab -l 2>/dev/null | grep -q rsync && backup_tool="${backup_tool:+$backup_tool + }rsync (cron)"

  [[ -n "$backup_tool" ]] \
    && bp_check "backup"      "Outil de backup détecté : ${backup_tool}" ok  "" \
    || bp_check "backup"      "Aucun outil de backup détecté"           fail "Installer borgbackup ou restic + configurer un cron de sauvegarde"

  # ── IPv6 ─────────────────────────────────────────────────────
  local ipv6_disabled
  ipv6_disabled=$(sysctl -n net.ipv6.conf.all.disable_ipv6 2>/dev/null || echo "0")
  if [[ "$ipv6_disabled" == "1" ]]; then
    bp_check "ipv6"           "IPv6 désactivé"                          ok   "Surface d'attaque réduite si IPv6 non utilisé"
  else
    # IPv6 actif — ok SI des adresses IPv6 sont effectivement utilisées
    local has_ipv6_addr
    has_ipv6_addr=$(ip -6 addr show scope global 2>/dev/null | { grep -c 'inet6' || true; })
    [[ "$has_ipv6_addr" -gt 0 ]] \
      && bp_check "ipv6"      "IPv6 actif et utilisé"                   ok   "${has_ipv6_addr} adresse(s) globale(s)" \
      || bp_check "ipv6"      "IPv6 actif mais aucune adresse globale"  warn "Désactiver si inutilisé : net.ipv6.conf.all.disable_ipv6=1 dans /etc/sysctl.conf"
  fi

  # ── rsyslog ──────────────────────────────────────────────────
  cmd_exists rsyslogd || cmd_exists syslogd \
    && bp_check "syslog"      "syslog présent"                          ok   "" \
    || bp_check "syslog"      "rsyslog absent (journald seul)"          warn "apt install rsyslog pour logs compatibles outils tiers"
}

render_bestpractices_section() {
  section "bestpractices" "✅" "Bonnes pratiques &amp; Outils recommandés"

  local ok_count=0 warn_count=0 fail_count=0
  for entry in "${BP_RESULTS[@]}"; do
    IFS='|' read -r _ _ status _ <<< "$entry"
    case "$status" in
      ok)   ok_count=$((ok_count+1)) ;;
      warn) warn_count=$((warn_count+1)) ;;
      fail) fail_count=$((fail_count+1)) ;;
    esac
  done

  # Score
  [[ $fail_count -ge 3 ]] && score_penalty 15 "Nombreuses bonnes pratiques non respectées (${fail_count} fails)"
  [[ $fail_count -ge 1 && $fail_count -lt 3 ]] && score_penalty 7 "${fail_count} bonne(s) pratique(s) critique(s) manquante(s)"
  [[ $warn_count -ge 5 ]] && score_penalty 5 "Plusieurs recommandations non appliquées (${warn_count} warnings)"

  # Résumé
  cards_start
  card "OK"       "$ok_count"   "green"
  card "À faire"  "$warn_count" "$([ $warn_count -gt 0 ] && echo yellow || echo green)"
  card "Critique" "$fail_count" "$([ $fail_count -gt 0 ] && echo red    || echo green)"
  cards_end

  echo "<br>"

  table_start "Check" "État" "Détail / Commande"
  for entry in "${BP_RESULTS[@]}"; do
    IFS='|' read -r id label status detail <<< "$entry"
    local dot
    dot=$(status_dot "$status")
    row "<span style='color:var(--muted);font-size:10px'>${id}</span>" \
        "${dot} ${label}" \
        "<span style='color:var(--muted)'>${detail}</span>"
  done
  table_end

  close_section
}
