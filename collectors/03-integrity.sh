#!/usr/bin/env bash
# ================================================================
#  collectors/03-integrity.sh — Lynis, rkhunter, chkrootkit,
#  debsums, AIDE, fail2ban, kernel params, certs, services
# ================================================================

collect_services() {
  log "Services..."
  if cmd_exists systemctl; then
    FAILED_UNITS=$(systemctl --failed --no-legend 2>/dev/null || echo "")
    SERVICES_RUNNING=$(systemctl list-units --type=service --state=running --no-legend 2>/dev/null | head -30 || echo "N/A")
    SERVICES_ENABLED=$(systemctl list-unit-files --type=service --state=enabled --no-legend 2>/dev/null | head -30 || echo "N/A")
  else
    FAILED_UNITS="systemctl non disponible"
    SERVICES_RUNNING="N/A"; SERVICES_ENABLED="N/A"
  fi
}

collect_certs() {
  log "Certificats TLS..."
  CERTS_INFO=""
  for dir in /etc/letsencrypt/live /usr/local/etc/letsencrypt/live; do
    [[ -d "$dir" ]] || continue
    while IFS= read -r -d '' cert; do
      expiry=$(openssl x509 -enddate -noout -in "$cert" 2>/dev/null | cut -d'=' -f2 || continue)
      domain=$(openssl x509 -subject -noout -in "$cert" 2>/dev/null \
        | grep -oE 'CN\s*=\s*[^,/]+' | head -1 | cut -d'=' -f2 | xargs || echo "?")
      expiry_epoch=$(date -d "$expiry" +%s 2>/dev/null || date -j -f "%b %d %T %Y %Z" "$expiry" +%s 2>/dev/null || echo 0)
      days_left=$(( (expiry_epoch - $(date +%s)) / 86400 ))
      if   [[ $days_left -le 7  ]]; then cert_status="fail"
      elif [[ $days_left -le 30 ]]; then cert_status="warn"
      else cert_status="ok"; fi
      [ -n "$domain" ] && CERTS_INFO="${CERTS_INFO}${domain}|${expiry}|${days_left}|${cert_status}\n"
    done < <(find "$dir" -name "*.pem" -o -name "*.crt" 2>/dev/null | head -15 | tr '\n' '\0')
  done
  CERTS_INFO="${CERTS_INFO:-none}"
}

collect_kernel_params() {
  log "Paramètres noyau..."
  KERNEL_PARAMS=""
  local params=(
    "net.ipv4.ip_forward" "net.ipv4.conf.all.accept_redirects"
    "net.ipv4.conf.all.send_redirects" "net.ipv4.conf.all.rp_filter"
    "net.ipv4.tcp_syncookies" "kernel.randomize_va_space"
    "kernel.dmesg_restrict" "kernel.kptr_restrict"
    "net.ipv4.conf.all.log_martians" "fs.protected_hardlinks" "fs.protected_symlinks"
  )
  local warn_count=0
  for param in "${params[@]}"; do
    local val s
    val=$(sysctl -n "$param" 2>/dev/null || echo "N/A")
    case "$param" in
      net.ipv4.ip_forward)                [[ "$val" == "0" ]] && s="ok" || s="warn" ;;
      net.ipv4.conf.all.accept_redirects) [[ "$val" == "0" ]] && s="ok" || s="warn" ;;
      net.ipv4.conf.all.send_redirects)   [[ "$val" == "0" ]] && s="ok" || s="warn" ;;
      net.ipv4.conf.all.rp_filter)        [[ "$val" == "1" ]] && s="ok" || s="warn" ;;
      net.ipv4.tcp_syncookies)            [[ "$val" == "1" ]] && s="ok" || s="warn" ;;
      kernel.randomize_va_space)          [[ "$val" == "2" ]] && s="ok" || s="warn" ;;
      kernel.dmesg_restrict)              [[ "$val" == "1" ]] && s="ok" || s="warn" ;;
      kernel.kptr_restrict)               [[ "$val" =~ ^[12]$ ]] && s="ok" || s="warn" ;;
      net.ipv4.conf.all.log_martians)     [[ "$val" == "1" ]] && s="ok" || s="warn" ;;
      fs.protected_hardlinks)             [[ "$val" == "1" ]] && s="ok" || s="warn" ;;
      fs.protected_symlinks)              [[ "$val" == "1" ]] && s="ok" || s="warn" ;;
      *)                                  s="gray" ;;
    esac
    [[ "$s" == "warn" ]] && warn_count=$((warn_count+1))
    KERNEL_PARAMS+="${param}|${val}|${s}\n"
  done
  KERNEL_WARN_COUNT=$warn_count
}

collect_fail2ban() {
  log "fail2ban..."
  FAIL2BAN_AVAILABLE=false; FAIL2BAN_STATUS=""; FAIL2BAN_JAILS=""
  if cmd_exists fail2ban-client; then
    FAIL2BAN_AVAILABLE=true
    FAIL2BAN_STATUS=$(fail2ban-client status 2>/dev/null || echo "Erreur connexion fail2ban")
    local jails
    jails=$(fail2ban-client status 2>/dev/null | grep 'Jail list' | cut -d':' -f2 | tr ',' '\n' | xargs || echo "")
    for jail in $jails; do
      local detail
      detail=$(fail2ban-client status "$jail" 2>/dev/null || echo "N/A")
      FAIL2BAN_JAILS+="=== Jail: ${jail} ===\n${detail}\n\n"
    done
    FAIL2BAN_JAILS="${FAIL2BAN_JAILS:-Aucune jail active}"
  fi
}

collect_lynis() {
  log "Lynis..."
  LYNIS_AVAILABLE=false; LYNIS_OUTPUT=""; LYNIS_SCORE=""
  if cmd_exists lynis; then
    LYNIS_AVAILABLE=true
    log "  lynis audit system (peut prendre 1-2 min)..."
    LYNIS_OUTPUT=$(lynis audit system --quick --no-colors 2>/dev/null \
      | grep -E 'Warning|Suggestion|Hardening index|Tests performed' | head -60 || echo "Erreur lynis")
    LYNIS_SCORE=$(echo "$LYNIS_OUTPUT" | grep 'Hardening index' | grep -oE '[0-9]+' | head -1 || echo "")
  fi
}

collect_rkhunter() {
  log "rkhunter..."
  RKHUNTER_AVAILABLE=false; RKHUNTER_OUTPUT=""
  if cmd_exists rkhunter && "${IS_ROOT:-false}"; then
    RKHUNTER_AVAILABLE=true
    rkhunter --update --quiet 2>/dev/null || true
    log "  Scan rkhunter..."
    RKHUNTER_OUTPUT=$(rkhunter --check --skip-keypress --quiet --no-colors 2>/dev/null \
      | grep -E 'Warning|Found|Infected|Rootkit' | head -40 || echo "Aucun résultat ou erreur")
  fi
}

collect_chkrootkit() {
  log "chkrootkit..."
  CHKROOTKIT_AVAILABLE=false; CHKROOTKIT_OUTPUT=""
  if cmd_exists chkrootkit && "${IS_ROOT:-false}"; then
    CHKROOTKIT_AVAILABLE=true
    log "  Scan chkrootkit..."
    CHKROOTKIT_OUTPUT=$(chkrootkit 2>/dev/null | grep -iE 'INFECTED|Vulnerable|not clean' | head -30 || echo "")
    CHKROOTKIT_OUTPUT="${CHKROOTKIT_OUTPUT:-Aucune infection détectée}"
  fi
}

collect_debsums() {
  log "debsums..."
  DEBSUMS_AVAILABLE=false; DEBSUMS_OUTPUT=""
  if cmd_exists debsums && "${IS_ROOT:-false}"; then
    DEBSUMS_AVAILABLE=true
    log "  Vérification debsums..."
    DEBSUMS_OUTPUT=$(debsums -s 2>/dev/null | head -30 || echo "")
    DEBSUMS_OUTPUT="${DEBSUMS_OUTPUT:-Tous les fichiers vérifiés OK}"
  fi
}

collect_aide() {
  log "AIDE..."
  AIDE_AVAILABLE=false; AIDE_OUTPUT=""
  if cmd_exists aide && "${IS_ROOT:-false}"; then
    AIDE_AVAILABLE=true
    if [[ -f /var/lib/aide/aide.db ]]; then
      AIDE_OUTPUT=$(aide --check 2>/dev/null | grep -E 'changed|added|removed' | head -30 || echo "")
      AIDE_OUTPUT="${AIDE_OUTPUT:-✓ Aucun changement détecté par AIDE}"
    else
      AIDE_OUTPUT="Base AIDE non initialisée. Lancer : aide --init && mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db"
    fi
  fi
}

collect_trivy_system() {
  log "Trivy (CVE système)..."
  TRIVY_SYS_AVAILABLE=false; TRIVY_SYS_OUTPUT=""
  if cmd_exists trivy; then
    TRIVY_SYS_AVAILABLE=true
    log "  Trivy rootfs scan..."
    TRIVY_SYS_OUTPUT=$(trivy rootfs --severity HIGH,CRITICAL --no-progress / 2>/dev/null \
      | grep -E 'CVE|Total|CRITICAL|HIGH' | head -40 || echo "Erreur scan trivy rootfs")
  fi
}

collect_secrets() {
  log "Secrets exposés..."
  local pattern='(password|passwd|secret|api_key|apikey|token|private_key|aws_access|aws_secret)\s*[=:]\s*\S+'
  SECRETS_FOUND=""
  local dirs=("/etc" "/opt" "/home" "/root" "/var/www" "/srv" "/app")
  for dir in "${dirs[@]}"; do
    [[ -d "$dir" ]] || continue
    while IFS= read -r -d '' file; do
      [[ $(file -b "$file" 2>/dev/null) =~ "text" ]] || continue
      [[ $(wc -c < "$file" 2>/dev/null) -gt 500000 ]] && continue
      local matches
      matches=$(grep -inE "$pattern" "$file" 2>/dev/null \
        | grep -vE '^#|example|sample|placeholder|changeme|your_|<' | head -3 || true)
      if [[ -n "$matches" ]]; then
        local masked
        masked=$(echo "$matches" | sed -E 's/([=:]\s*)\S{4,}/\1[MASQUÉ]/g')
        SECRETS_FOUND+="📄 ${file}\n${masked}\n\n"
      fi
    done < <(find "$dir" -maxdepth 4 -type f \
      \( -name "*.env" -o -name "*.conf" -o -name "*.cfg" -o -name "*.ini" \
         -o -name "*.yaml" -o -name "*.yml" -o -name "*.json" -o -name "*.toml" \
         -o -name ".env*" \) 2>/dev/null | tr '\n' '\0')
  done
  SECRETS_FOUND="${SECRETS_FOUND:-Aucun pattern suspect détecté}"
  ENV_SECRETS=$(env 2>/dev/null | grep -iE 'password|secret|token|key|api' \
    | sed -E 's/=.*/=[MASQUÉ]/' || echo "Aucune variable sensible dans env")
}

collect_history() {
  log "Historique..."
  HISTORY_ROOT=$(tail -n 30 /root/.bash_history 2>/dev/null || tail -n 30 /root/.zsh_history 2>/dev/null || echo "Non accessible")
}

# ── Rendering ────────────────────────────────────────────────

render_certs_section() {
  section "certs" "🔒" "Certificats TLS"
  if [[ "$CERTS_INFO" == "none" ]]; then
    alert "blue" "ℹ" "Aucun certificat .pem/.crt trouvé dans les emplacements standards"
  else
    table_start "Domaine" "Expiration" "Jours restants" "État"
    while IFS='|' read -r domain expiry days s; do
      [[ -z "$domain" ]] && continue
      row "$domain" "$expiry" "$days" "$(status_dot "$s") $s"
      [[ "$s" == "fail" ]] && score_penalty 15 "Certificat TLS expiré ou expirant sous 7j (${domain})"
    done < <(echo -e "$CERTS_INFO")
    table_end
  fi
  close_section
}

render_services_section() {
  section "services" "⚡" "Services Systemd"
  if [[ -n "${FAILED_UNITS:-}" ]]; then
    alert "red" "⚠" "Units en échec :"
    pre_block "$FAILED_UNITS"
    score_penalty 5 "Services systemd en échec"
  else
    alert "green" "✓" "Aucune unit systemd en échec"
  fi
  h3 "Services actifs"
  pre_block "$SERVICES_RUNNING"
  h3 "Services activés au démarrage"
  pre_block "$SERVICES_ENABLED"
  close_section
}

render_kernel_section() {
  section "kernel" "🧠" "Paramètres noyau (sécurité)"
  table_start "Paramètre" "Valeur" "État"
  while IFS='|' read -r param val s; do
    [[ -z "$param" ]] && continue
    row "$param" "$val" "$(status_dot "$s")"
  done < <(echo -e "$KERNEL_PARAMS")
  table_end
  [[ "${KERNEL_WARN_COUNT:-0}" -ge 4 ]] && score_penalty 5 "Plusieurs paramètres kernel hors recommandations sécurité"
  close_section
}

render_fail2ban_section() {
  section "fail2ban" "🛡" "fail2ban"
  if $FAIL2BAN_AVAILABLE; then
    alert "green" "✓" "fail2ban installé et opérationnel"
    h3 "Statut global"
    pre_block "$FAIL2BAN_STATUS"
    h3 "Détail par jail"
    pre_block "$(echo -e "$FAIL2BAN_JAILS")"
  else
    alert "red" "⚠" "fail2ban non installé — les attaques SSH bruteforce ne sont pas bloquées automatiquement"
    echo "<div style='font-size:11px;color:var(--muted)'>Installation : <code>apt install fail2ban</code></div>"
    score_penalty 10 "fail2ban non installé"
  fi
  close_section
}

render_lynis_section() {
  section "lynis" "📋" "Lynis — Audit CIS"
  if $LYNIS_AVAILABLE; then
    if [[ -n "$LYNIS_SCORE" ]]; then
      echo "$(badge "Hardening index" "${LYNIS_SCORE}/100" "$([ "${LYNIS_SCORE:-0}" -ge 70 ] && echo green || { [ "${LYNIS_SCORE:-0}" -ge 50 ] && echo yellow || echo red; })")<br><br>"
      [[ "${LYNIS_SCORE:-100}" -lt 50 ]] && score_penalty 10 "Hardening index Lynis faible (${LYNIS_SCORE}/100)"
    fi
    pre_block "$LYNIS_OUTPUT"
  else
    alert "blue" "ℹ" "lynis non installé"
    echo "<div style='font-size:11px;color:var(--muted);margin-top:8px'>Installation : <code>apt install lynis</code></div>"
  fi
  close_section
}

render_rootkits_section() {
  section "rootkits" "🦠" "Détection Rootkits"
  echo "<div style='margin-bottom:16px'>"
  echo "$(badge "rkhunter" "$($RKHUNTER_AVAILABLE && echo "présent" || echo "absent")" "$($RKHUNTER_AVAILABLE && echo blue || echo gray)")<br><br>"
  if $RKHUNTER_AVAILABLE; then
    if echo "$RKHUNTER_OUTPUT" | grep -qi 'warning\|found\|infected'; then
      alert "red" "⚠" "rkhunter a détecté des anomalies"
      score_penalty 20 "rkhunter a détecté des anomalies"
    else
      alert "green" "✓" "rkhunter : aucune anomalie"
    fi
    pre_block "$RKHUNTER_OUTPUT"
  else
    alert "blue" "ℹ" "rkhunter non installé : <code>apt install rkhunter</code>"
  fi
  echo "</div>"
  echo "$(badge "chkrootkit" "$($CHKROOTKIT_AVAILABLE && echo "présent" || echo "absent")" "$($CHKROOTKIT_AVAILABLE && echo blue || echo gray)")<br><br>"
  if $CHKROOTKIT_AVAILABLE; then
    if echo "$CHKROOTKIT_OUTPUT" | grep -qiE 'INFECTED|Vulnerable'; then
      alert "red" "⚠" "chkrootkit a détecté des infections"
      score_penalty 20 "chkrootkit a détecté des infections"
    else
      alert "green" "✓" "chkrootkit : aucune infection"
    fi
    pre_block "$CHKROOTKIT_OUTPUT"
  else
    alert "blue" "ℹ" "chkrootkit non installé : <code>apt install chkrootkit</code>"
  fi
  close_section
}

render_integrity_section() {
  section "integrity" "🗄" "Intégrité des fichiers"
  echo "$(badge "debsums" "$($DEBSUMS_AVAILABLE && echo "présent" || echo "absent")" "$($DEBSUMS_AVAILABLE && echo blue || echo gray)")"
  echo "$(badge "aide" "$($AIDE_AVAILABLE && echo "présent" || echo "absent")" "$($AIDE_AVAILABLE && echo blue || echo gray)")<br><br>"
  if $DEBSUMS_AVAILABLE; then
    h3 "debsums — Intégrité des packages"
    if echo "$DEBSUMS_OUTPUT" | grep -qiE 'FAILED|changed'; then
      alert "red" "⚠" "Fichiers de packages modifiés détectés !"
      score_penalty 15 "debsums : fichiers de packages modifiés"
    else
      alert "green" "✓" "Tous les fichiers packages vérifiés OK"
    fi
    pre_block "$DEBSUMS_OUTPUT"
  else
    alert "blue" "ℹ" "debsums non installé : <code>apt install debsums</code>"
  fi
  if $AIDE_AVAILABLE; then
    h3 "AIDE — Intégrité système de fichiers"
    pre_block "$AIDE_OUTPUT"
  else
    alert "blue" "ℹ" "aide non installé : <code>apt install aide && aide --init</code>"
  fi
  close_section
}

render_secrets_section() {
  section "secrets" "🔏" "Secrets &amp; Credentials exposés"
  h3 "Scan fichiers de configuration (valeurs masquées)"
  if echo "$SECRETS_FOUND" | grep -q "📄"; then
    alert "yellow" "⚡" "Patterns potentiellement sensibles trouvés (valeurs masquées) :"
    pre_block "$SECRETS_FOUND"
    score_penalty 10 "Secrets potentiels détectés dans des fichiers de config"
  else
    alert "green" "✓" "Aucun pattern suspect dans les fichiers de config scannés"
  fi
  h3 "Variables d'environnement sensibles"
  pre_block "$ENV_SECRETS"
  close_section
}

render_trivy_section() {
  section "trivy" "🔍" "Trivy — CVE Système"
  if $TRIVY_SYS_AVAILABLE; then
    if echo "$TRIVY_SYS_OUTPUT" | grep -q CRITICAL; then
      score_penalty 10 "CVE CRITICAL détectées par Trivy sur le système"
    fi
    pre_block "$TRIVY_SYS_OUTPUT"
  else
    alert "blue" "ℹ" "trivy non installé"
    echo "<div style='font-size:11px;color:var(--muted);margin-top:8px'>Installation : <code>curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin</code></div>"
  fi
  close_section
}

render_history_section() {
  section "history" "📜" "Historique root"
  pre_block "$HISTORY_ROOT"
  close_section
}
