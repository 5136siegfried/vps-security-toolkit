#!/usr/bin/env bash
# ================================================================
#  collectors/02-auth.sh — SSH, utilisateurs, privilèges, SUID
# ================================================================

collect_auth() {
  log "Authentification SSH..."
  AUTH_LOG=""; AUTH_LOG_FILE=""
  for f in /var/log/auth.log /var/log/secure /var/log/audit/audit.log; do
    if [[ -f "$f" && -r "$f" ]]; then
      AUTH_LOG=$(grep -iE 'sshd|Failed|Accepted|Invalid|authentication failure' "$f" 2>/dev/null | tail -40 || true)
      AUTH_LOG_FILE="$f"; break
    fi
  done
  if [[ -z "$AUTH_LOG" ]] && cmd_exists journalctl; then
    AUTH_LOG=$(journalctl -u ssh -u sshd --no-pager -n 80 2>/dev/null \
      | grep -iE 'Failed|Accepted|Invalid' | tail -40 || true)
    AUTH_LOG_FILE="journalctl (ssh/sshd)"
  fi
  [[ -z "$AUTH_LOG_FILE" ]] && AUTH_LOG_FILE="non accessible"
  ACTIVE_SESSIONS=$(w 2>/dev/null || who 2>/dev/null || echo "N/A")
  LAST_LOGINS=$(last -n 20 2>/dev/null || echo "N/A")
  FAILED_COUNT=$(echo "$AUTH_LOG" | { grep -icE 'failed|invalid' || true; })
  BRUTE_IPS=$(echo "$AUTH_LOG" | grep -iE 'Failed|Invalid' \
    | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' \
    | sort | uniq -c | sort -rn | head -10 || echo "")
}

collect_ssh_config() {
  log "Config SSH..."
  SSH_CFG_FILE="/etc/ssh/sshd_config"
  SSH_CONFIG_CHECKS=""
  if [[ -f "$SSH_CFG_FILE" ]]; then
    _check_ssh_param() {
      local param="$1" expected="$2"
      local val
      val=$(grep -iE "^${param}\s" "$SSH_CFG_FILE" 2>/dev/null | awk '{print $2}' | head -1 || echo "default")
      local s
      [[ "$val" == "$expected" ]] && s="ok" || s="warn"
      echo "${param}|${val:-default}|${expected}|${s}"
    }
    SSH_CONFIG_CHECKS+="$(_check_ssh_param PermitRootLogin no)\n"
    SSH_CONFIG_CHECKS+="$(_check_ssh_param PasswordAuthentication no)\n"
    SSH_CONFIG_CHECKS+="$(_check_ssh_param PermitEmptyPasswords no)\n"
    SSH_CONFIG_CHECKS+="$(_check_ssh_param X11Forwarding no)\n"
    SSH_CONFIG_CHECKS+="$(_check_ssh_param MaxAuthTries 3)\n"
    SSH_CONFIG_CHECKS+="$(_check_ssh_param ClientAliveInterval 300)\n"
    SSH_CONFIG_CHECKS+="$(_check_ssh_param AllowAgentForwarding no)\n"
    SSH_CONFIG_CHECKS+="$(_check_ssh_param PubkeyAuthentication yes)\n"
  else
    SSH_CONFIG_CHECKS="Fichier sshd_config introuvable"
  fi
  SSH_CONFIG_RAW=$(cat "$SSH_CFG_FILE" 2>/dev/null | grep -vE '^#|^$' | head -30 || echo "N/A")
}

collect_users() {
  log "Utilisateurs..."
  USERS_LIST=$(awk -F: '$7 !~ /nologin|false|sync|halt|shutdown/ && $3 >= 0 \
    {print $1":"$3":"$4":"$6":"$7}' /etc/passwd 2>/dev/null)
  UID0_OTHERS=$(awk -F: '$3==0 && $1!="root"{print $1}' /etc/passwd 2>/dev/null || echo "")
  SUDO_MEMBERS=$(getent group sudo wheel 2>/dev/null | tr ':' ' ' | awk '{print $1": "$4}' || echo "N/A")
  SSH_KEYS=""
  while IFS=: read -r user _ _ _ _ home _; do
    keyfile="${home}/.ssh/authorized_keys"
    if [[ -f "$keyfile" && -r "$keyfile" ]]; then
      count=$(wc -l < "$keyfile" 2>/dev/null || echo "?")
      SSH_KEYS+="${user}: ${count} clé(s)\n"
    fi
  done < /etc/passwd
  [[ -z "$SSH_KEYS" ]] && SSH_KEYS="Aucune authorized_keys trouvée"
  SUDOERS=$(grep -vE '^#|^$|^Defaults' /etc/sudoers 2>/dev/null | head -20 || echo "N/A (permission refusée)")
  CRON_ROOT=$(crontab -l 2>/dev/null || echo "(vide)")
  CRON_SYSD=$(ls -la /etc/cron.d/ 2>/dev/null || echo "(vide)")
  CRON_ALL=""
  for u in $(cut -d: -f1 /etc/passwd); do
    ct=$(crontab -u "$u" -l 2>/dev/null | grep -v '^#' | grep -v '^$' || true)
    [[ -n "$ct" ]] && CRON_ALL+="=== $u ===\n${ct}\n"
  done
  [[ -z "$CRON_ALL" ]] && CRON_ALL="(aucune crontab utilisateur)"
}

collect_suid_sgid() {
  log "SUID/SGID..."
  SUID_FILES=$(find / -xdev -perm -4000 -type f 2>/dev/null | sort || echo "N/A")
  SGID_FILES=$(find / -xdev -perm -2000 -type f 2>/dev/null | sort | head -20 || echo "N/A")
  WORLD_WRITABLE=$(find / -xdev -perm -0002 -not -type l -not -path '/proc/*' \
    -not -path '/sys/*' 2>/dev/null | head -20 || echo "N/A")
}

render_auth_section() {
  section "auth" "🔐" "Accès &amp; Tentatives SSH"
  if   [[ $FAILED_COUNT -gt 50 ]]; then
    alert "red" "🚨" "${FAILED_COUNT} tentatives échouées — bruteforce probable"
    score_penalty 15 "Bruteforce SSH (${FAILED_COUNT} échecs)"
  elif [[ $FAILED_COUNT -gt 10 ]]; then
    alert "yellow" "⚡" "${FAILED_COUNT} tentatives d'authentification échouées"
    score_penalty 5 "Tentatives SSH suspectes (${FAILED_COUNT})"
  else
    alert "green" "✓" "${FAILED_COUNT} tentatives échouées récentes"
  fi
  if [[ -n "${BRUTE_IPS:-}" ]]; then
    h3 "Top IPs brute-force"
    table_start "Tentatives" "IP"
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      row "$(echo "$line" | awk '{print $1}')" "$(echo "$line" | awk '{print $2}')"
    done <<< "$BRUTE_IPS"
    table_end
  fi
  h3 "Sessions actives"
  pre_block "$ACTIVE_SESSIONS"
  h3 "Dernières connexions"
  pre_block "$LAST_LOGINS"
  h3 "Logs (source : ${AUTH_LOG_FILE})"
  pre_block "$AUTH_LOG"
  close_section
}

render_sshcfg_section() {
  section "sshcfg" "🔑" "Configuration sshd"
  if [[ "$SSH_CONFIG_CHECKS" != "Fichier sshd_config introuvable" ]]; then
    table_start "Paramètre" "Valeur actuelle" "Recommandé" "État"
    local warn_count=0
    while IFS='|' read -r param val expected s; do
      [[ -z "$param" ]] && continue
      [[ "$s" == "warn" ]] && warn_count=$((warn_count+1))
      row "$param" "$val" "$expected" "$(status_dot "$s")"
    done < <(echo -e "$SSH_CONFIG_CHECKS")
    table_end
    [[ $warn_count -ge 3 ]] && score_penalty 10 "Configuration sshd faible (${warn_count} paramètres hors recommandation)"
    h3 "sshd_config (actif)"
    pre_block "$SSH_CONFIG_RAW"
  else
    alert "yellow" "⚠" "$SSH_CONFIG_CHECKS"
  fi
  close_section
}

render_users_section() {
  section "users" "👤" "Utilisateurs &amp; Privilèges"
  if [[ -n "${UID0_OTHERS:-}" ]]; then
    alert "red" "🚨" "Comptes avec UID 0 non-root détectés : ${UID0_OTHERS}"
    score_penalty 20 "Comptes UID 0 non-root détectés"
  fi
  h3 "Comptes avec shell actif"
  table_start "Utilisateur" "UID" "GID" "Home" "Shell"
  while IFS=: read -r user uid gid home shell; do
    row "$user" "$uid" "$gid" "$home" "$shell"
  done <<< "$USERS_LIST"
  table_end
  h3 "Membres sudo / wheel"
  pre_block "$SUDO_MEMBERS"
  h3 "Clés SSH autorisées"
  pre_block "$(echo -e "$SSH_KEYS")"
  h3 "Sudoers (extrait)"
  pre_block "$SUDOERS"
  close_section
}

render_cron_section() {
  section "cron" "⏱" "Crontabs"
  h3 "Crontab root"
  pre_block "$CRON_ROOT"
  h3 "Fichiers /etc/cron.d/"
  pre_block "$CRON_SYSD"
  h3 "Crontabs utilisateurs"
  pre_block "$(echo -e "$CRON_ALL")"
  close_section
}

render_suid_section() {
  section "suid" "⚠" "Fichiers SUID / SGID / World-Writable"
  h3 "Fichiers SUID"
  pre_block "$SUID_FILES"
  h3 "Fichiers SGID (top 20)"
  pre_block "$SGID_FILES"
  h3 "Fichiers world-writable (top 20)"
  if [[ -n "${WORLD_WRITABLE:-}" ]]; then
    alert "yellow" "⚡" "Fichiers inscriptibles par tous :"
    pre_block "$WORLD_WRITABLE"
    score_penalty 5 "Fichiers world-writable détectés"
  else
    alert "green" "✓" "Aucun fichier world-writable non-symlink trouvé"
  fi
  close_section
}
