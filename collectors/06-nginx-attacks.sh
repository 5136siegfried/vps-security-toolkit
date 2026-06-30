#!/usr/bin/env bash
# ================================================================
#  collectors/06-nginx-attacks.sh — Détection d'attaques web
#  via parsing des access logs Nginx (format combiné).
#
#  Config (option B — par variable d'env ou fichier par hôte) :
#    NGINX_LOG_PATHS  — liste de chemins séparés par des virgules
#                        ex: "/var/log/nginx/site1.access.log,/var/log/nginx/site2.access.log"
#                        Si non défini : tente la convention par défaut
#                        /var/log/nginx/*access*.log
#    NGINX_LOG_LINES  — profondeur d'analyse (défaut 5000 dernières lignes/fichier)
# ================================================================

collect_nginx_attacks() {
  log "Nginx — analyse access logs..."
  NGINX_LOG_LINES="${NGINX_LOG_LINES:-5000}"
  NGINX_AVAILABLE=false
  NGINX_LOG_FILES=()

  if [[ -n "${NGINX_LOG_PATHS:-}" ]]; then
    IFS=',' read -ra _paths <<< "$NGINX_LOG_PATHS"
    for p in "${_paths[@]}"; do
      p_trimmed=$(echo "$p" | xargs)
      [[ -f "$p_trimmed" && -r "$p_trimmed" ]] && NGINX_LOG_FILES+=("$p_trimmed")
    done
  else
    while IFS= read -r f; do
      NGINX_LOG_FILES+=("$f")
    done < <(find /var/log/nginx -maxdepth 1 -iname "*access*.log" -readable 2>/dev/null || true)
  fi

  [[ ${#NGINX_LOG_FILES[@]} -eq 0 ]] && return 0
  NGINX_AVAILABLE=true

  NGINX_TOTAL_REQUESTS=0
  NGINX_4XX_COUNT=0
  NGINX_5XX_COUNT=0
  NGINX_TOP_4XX_IPS=""
  NGINX_TOP_5XX_IPS=""
  NGINX_TOP_PATHS=""
  NGINX_INJECTION_HITS=""
  NGINX_SCANNER_UA=""
  NGINX_PER_FILE_SUMMARY=""

  # Patterns d'injection / path traversal / scanners courants dans l'URI
  local injection_pattern='(\.\./|\.\.%2f|<script|union[[:space:]]+select|select.+from|/etc/passwd|/wp-admin|/wp-login|xp_cmdshell|base64_decode|eval\(|\.\.\\|%00|\.\.;/|/phpmyadmin|/\.env|/\.git/|cmd=|exec\(|\bOR\b 1=1|drop[[:space:]]+table)'
  # User-Agents de scanners connus
  local scanner_ua_pattern='(nikto|sqlmap|nmap|masscan|nessus|acunetix|w3af|dirbuster|gobuster|wpscan|metasploit|zgrab|shodan|censys|python-requests.*bot|curl/7\.[0-9]+.*scan)'

  for logfile in "${NGINX_LOG_FILES[@]}"; do
    local data
    data=$(tail -n "$NGINX_LOG_LINES" "$logfile" 2>/dev/null || echo "")
    [[ -z "$data" ]] && continue

    local file_total
    file_total=$(echo "$data" | wc -l)
    NGINX_TOTAL_REQUESTS=$(( NGINX_TOTAL_REQUESTS + file_total ))

    # Format combiné standard : $remote_addr - - [date] "METHOD path HTTP/x" status size "referer" "ua"
    # Codes 4xx
    local f4xx f5xx
    f4xx=$(echo "$data" | grep -oE '" [4][0-9]{2} ' | wc -l || echo 0)
    f5xx=$(echo "$data" | grep -oE '" [5][0-9]{2} ' | wc -l || echo 0)
    NGINX_4XX_COUNT=$(( NGINX_4XX_COUNT + f4xx ))
    NGINX_5XX_COUNT=$(( NGINX_5XX_COUNT + f5xx ))

    NGINX_PER_FILE_SUMMARY+="${logfile}|${file_total}|${f4xx}|${f5xx}\n"

    # Top IPs en 4xx (bruteforce / scan endpoints)
    NGINX_TOP_4XX_IPS+=$(echo "$data" | awk '$9 ~ /^4[0-9][0-9]$/ {print $1}' | sort | uniq -c | sort -rn | head -10)
    NGINX_TOP_4XX_IPS+=$'\n'

    # Top IPs en 5xx (erreurs serveur déclenchées)
    NGINX_TOP_5XX_IPS+=$(echo "$data" | awk '$9 ~ /^5[0-9][0-9]$/ {print $1}' | sort | uniq -c | sort -rn | head -10)
    NGINX_TOP_5XX_IPS+=$'\n'

    # Top paths demandés
    NGINX_TOP_PATHS+=$(echo "$data" | awk -F'"' '{print $2}' | awk '{print $2}' | sort | uniq -c | sort -rn | head -15)
    NGINX_TOP_PATHS+=$'\n'

    # Patterns d'injection dans l'URI
    local inj
    inj=$(echo "$data" | grep -iE "$injection_pattern" | awk -F'"' '{print $1, $2}' | sort | uniq -c | sort -rn | head -20 || true)
    [[ -n "$inj" ]] && NGINX_INJECTION_HITS+="=== ${logfile} ===\n${inj}\n\n"

    # User-Agents de scanners
    local scan_ua
    scan_ua=$(echo "$data" | grep -ioE "\"[^\"]*(${scanner_ua_pattern})[^\"]*\"" | sort | uniq -c | sort -rn | head -10 || true)
    [[ -n "$scan_ua" ]] && NGINX_SCANNER_UA+="=== ${logfile} ===\n${scan_ua}\n\n"
  done

  # Nettoyage : suppression des lignes vides/0 dans les agrégats top IPs
  NGINX_TOP_4XX_IPS=$(echo "$NGINX_TOP_4XX_IPS" | grep -v '^\s*$' | sort -rn | head -10 || echo "")
  NGINX_TOP_5XX_IPS=$(echo "$NGINX_TOP_5XX_IPS" | grep -v '^\s*$' | sort -rn | head -10 || echo "")
  NGINX_TOP_PATHS=$(echo "$NGINX_TOP_PATHS" | grep -v '^\s*$' | sort -rn | head -15 || echo "")

  [[ "$NGINX_TOTAL_REQUESTS" -gt 0 ]] && \
    NGINX_4XX_RATE=$(( NGINX_4XX_COUNT * 100 / NGINX_TOTAL_REQUESTS )) || NGINX_4XX_RATE=0
  [[ "$NGINX_TOTAL_REQUESTS" -gt 0 ]] && \
    NGINX_5XX_RATE=$(( NGINX_5XX_COUNT * 100 / NGINX_TOTAL_REQUESTS )) || NGINX_5XX_RATE=0
}

render_nginx_section() {
  section "nginx" "🌐" "Nginx — Attaques &amp; Anomalies web"

  if ! $NGINX_AVAILABLE; then
    alert "blue" "ℹ" "Aucun access log Nginx trouvé. Configurer NGINX_LOG_PATHS (ex: /var/log/nginx/monsite.access.log,/var/log/nginx/autresite.access.log) ou vérifier /var/log/nginx/*access*.log"
    close_section
    return 0
  fi

  cards_start
  card "Requêtes analysées" "${NGINX_TOTAL_REQUESTS}" "blue"
  card "Taux 4xx" "${NGINX_4XX_RATE}%" "$(pct_color "$NGINX_4XX_RATE" 10 25)"
  card "Taux 5xx" "${NGINX_5XX_RATE}%" "$(pct_color "$NGINX_5XX_RATE" 5 15)"
  card "Fichiers analysés" "${#NGINX_LOG_FILES[@]}" "blue"
  cards_end

  if [[ "$NGINX_5XX_RATE" -ge 15 ]]; then
    score_penalty 10 "Taux d'erreurs 5xx élevé sur Nginx (${NGINX_5XX_RATE}%)"
  elif [[ "$NGINX_5XX_RATE" -ge 5 ]]; then
    score_penalty 5 "Taux d'erreurs 5xx notable sur Nginx (${NGINX_5XX_RATE}%)"
  fi

  h3 "Fichiers de logs analysés"
  table_start "Fichier" "Requêtes" "4xx" "5xx"
  while IFS='|' read -r f total c4 c5; do
    [[ -z "$f" ]] && continue
    row "$f" "$total" "$c4" "$c5"
  done < <(echo -e "$NGINX_PER_FILE_SUMMARY")
  table_end

  if [[ -n "$NGINX_INJECTION_HITS" ]]; then
    score_penalty 15 "Tentatives d'injection / path traversal détectées dans les access logs"
    alert "red" "🚨" "Patterns d'injection / traversal détectés dans les requêtes :"
    h3 "Requêtes suspectes (injection, traversal, fichiers sensibles)"
    pre_block "$NGINX_INJECTION_HITS"
  else
    alert "green" "✓" "Aucun pattern d'injection/traversal détecté dans les URIs"
  fi

  if [[ -n "$NGINX_SCANNER_UA" ]]; then
    score_penalty 5 "User-Agents de scanners de vulnérabilités détectés"
    h3 "User-Agents de scanners connus"
    pre_block "$NGINX_SCANNER_UA"
  fi

  h3 "Top IPs générant des 4xx"
  pre_block "$NGINX_TOP_4XX_IPS"

  h3 "Top IPs générant des 5xx"
  pre_block "$NGINX_TOP_5XX_IPS"

  h3 "Top endpoints demandés"
  pre_block "$NGINX_TOP_PATHS"

  close_section
}
