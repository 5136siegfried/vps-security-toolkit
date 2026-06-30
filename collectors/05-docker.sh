#!/usr/bin/env bash
# ================================================================
#  collectors/05-docker.sh — État Docker (containers, images, CVE)
#  Source : doit être sourcé après lib/html.sh et lib/score.sh
# ================================================================

collect_docker() {
  log "Docker..."
  DOCKER_AVAILABLE=false
  if cmd_exists docker && docker info &>/dev/null 2>&1; then
    DOCKER_AVAILABLE=true
    DOCKER_PS=$(docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || echo "Erreur")
    DOCKER_DANGLING=$(docker images -f "dangling=true" -q 2>/dev/null | wc -l || echo "0")
    DOCKER_VOLUMES=$(docker volume ls -q 2>/dev/null | wc -l || echo "0")
    DOCKER_PRIVILEGED=$(docker ps -q 2>/dev/null | xargs -I{} docker inspect {} \
      --format '{{.Name}}: privileged={{.HostConfig.Privileged}}' 2>/dev/null \
      | grep 'privileged=true' || echo "")
    DOCKER_IMAGES=$(docker images --format "{{.Repository}}:{{.Tag}}\t{{.Size}}\t{{.CreatedSince}}" 2>/dev/null | head -20 || echo "N/A")
    # Logging driver utilisé par container (utile pour savoir qui est déjà en JSON)
    DOCKER_LOG_DRIVERS=$(docker ps -q 2>/dev/null | xargs -I{} docker inspect {} \
      --format '{{.Name}}: {{.HostConfig.LogConfig.Type}}' 2>/dev/null || echo "N/A")

    TRIVY_RESULTS=""
    if cmd_exists trivy; then
      log "  trivy scan images Docker..."
      while IFS= read -r img; do
        [[ "$img" == "<none>:<none>" ]] && continue
        result=$(trivy image --severity HIGH,CRITICAL --no-progress "$img" 2>/dev/null | tail -25 || echo "Erreur scan $img")
        TRIVY_RESULTS+="=== $img ===\n${result}\n\n"
      done < <(docker images --format "{{.Repository}}:{{.Tag}}" 2>/dev/null | head -5)
    fi
  fi
}

# ── Logs des containers (stdout) ──────────────────────────────
# Convention : pas de chemin fixe, on lit via `docker logs` directement.
# DOCKER_LOG_LINES contrôle la profondeur (défaut 500 lignes/container).
collect_docker_logs() {
  log "Docker container logs..."
  DOCKER_LOG_LINES="${DOCKER_LOG_LINES:-500}"
  DOCKER_LOGS_SUMMARY=""
  DOCKER_LOGS_ERRORS=""
  DOCKER_RESTART_COUNTS=""

  if ! $DOCKER_AVAILABLE; then
    return 0
  fi

  # Patterns d'erreur génériques cross-langage (Python, Node, Go, Java, PHP, nginx upstream...)
  local err_pattern='(ERROR|Error|CRITICAL|FATAL|Exception|Traceback|panic:|segfault|OOMKilled|连接|refused|ECONNREFUSED|Unhandled|unhandled rejection|stack trace|core dumped|502 Bad Gateway|upstream timed out)'

  while IFS= read -r container; do
    [[ -z "$container" ]] && continue

    # Restart count — symptôme de crash loop
    restarts=$(docker inspect "$container" --format '{{.RestartCount}}' 2>/dev/null || echo "0")
    status=$(docker inspect "$container" --format '{{.State.Status}}' 2>/dev/null || echo "?")
    health=$(docker inspect "$container" --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}n/a{{end}}' 2>/dev/null || echo "n/a")
    DOCKER_RESTART_COUNTS+="${container}|${status}|${health}|${restarts}\n"

    # Récupère les N dernières lignes et grep les patterns d'erreur
    logs=$(docker logs --tail "$DOCKER_LOG_LINES" "$container" 2>&1 || echo "")
    error_lines=$(echo "$logs" | grep -E "$err_pattern" | tail -20 || true)
    error_count=$(echo "$logs" | { grep -cE "$err_pattern" 2>/dev/null || true; })

    if [[ "$error_count" -gt 0 ]]; then
      DOCKER_LOGS_ERRORS+="=== ${container} (${error_count} lignes suspectes / ${DOCKER_LOG_LINES} dernières) ===\n${error_lines}\n\n"
    fi

    DOCKER_LOGS_SUMMARY+="${container}|${error_count}\n"

  done < <(docker ps --format '{{.Names}}' 2>/dev/null)

  DOCKER_LOGS_SUMMARY="${DOCKER_LOGS_SUMMARY:-Aucun container actif}"
}

render_docker_section() {
  section "docker" "🐳" "Docker"
  if $DOCKER_AVAILABLE; then
    echo "$(badge "Dangling images" "${DOCKER_DANGLING}" "$([ "${DOCKER_DANGLING}" -gt 0 ] && echo yellow || echo green)")"
    echo "$(badge "Volumes" "${DOCKER_VOLUMES}" "blue")"
    echo "<br><br>"
    if [[ -n "${DOCKER_PRIVILEGED:-}" ]]; then
      alert "red" "🚨" "Conteneur(s) en mode --privileged :"
      pre_block "$DOCKER_PRIVILEGED"
      score_penalty 15 "Conteneur(s) Docker en mode privileged"
    else
      alert "green" "✓" "Aucun conteneur en mode privileged"
    fi
    h3 "Conteneurs actifs"
    pre_block "$DOCKER_PS"
    h3 "Images"
    pre_block "$DOCKER_IMAGES"
    h3 "Logging driver par conteneur"
    local non_json
    non_json=$(echo -e "$DOCKER_LOG_DRIVERS" | grep -vc 'json-file' || echo "0")
    if [[ "$non_json" -gt 0 ]]; then
    non_json=$(echo -e "$DOCKER_LOG_DRIVERS" | { grep -vc "json-file" || true; })
    fi
    pre_block "$DOCKER_LOG_DRIVERS"
    if [[ -n "${TRIVY_RESULTS:-}" ]]; then
      h3 "Trivy — scan images"
      pre_block "$TRIVY_RESULTS"
    fi
  else
    alert "blue" "ℹ" "Docker non installé ou inaccessible"
  fi
  close_section

  section "dockerlogs" "📋" "Docker — Logs applicatifs" "(stdout, ${DOCKER_LOG_LINES:-500} dernières lignes/conteneur)"
  if ! $DOCKER_AVAILABLE; then
    alert "blue" "ℹ" "Docker non disponible"
    close_section
    return 0
  fi

  h3 "État des conteneurs (status / health / restarts)"
  table_start "Conteneur" "Status" "Health" "Restarts"
  local restart_alert_fired=false
  while IFS='|' read -r name status health restarts; do
    [[ -z "$name" ]] && continue
    local rcell="$restarts"
    if [[ "$restarts" =~ ^[0-9]+$ && "$restarts" -ge 5 ]]; then
      rcell="<span style='color:var(--red);font-weight:700'>${restarts}</span>"
      restart_alert_fired=true
    fi
    row "$name" "$status" "$health" "$rcell"
  done < <(echo -e "$DOCKER_RESTART_COUNTS")
  table_end
  if $restart_alert_fired; then
    score_penalty 10 "Conteneur(s) en crash-loop (≥5 restarts)"
  fi

  h3 "Résumé erreurs par conteneur"
  table_start "Conteneur" "Lignes suspectes"
  local total_errors=0
  while IFS='|' read -r name count; do
    [[ -z "$name" ]] && continue
    local ccell="$count"
    [[ "$count" =~ ^[0-9]+$ && "$count" -gt 0 ]] && ccell="<span style='color:var(--yellow);font-weight:700'>${count}</span>"
    [[ "$count" =~ ^[0-9]+$ ]] && total_errors=$(( total_errors + count ))
    row "$name" "$ccell"
  done < <(echo -e "$DOCKER_LOGS_SUMMARY")
  table_end

  if [[ -n "${DOCKER_LOGS_ERRORS:-}" ]]; then
    if [[ $total_errors -gt 100 ]]; then
      score_penalty 10 "Volume élevé d'erreurs dans les logs Docker (${total_errors})"
    elif [[ $total_errors -gt 20 ]]; then
      score_penalty 5 "Erreurs détectées dans les logs Docker (${total_errors})"
    fi
    h3 "Extraits des lignes suspectes"
    pre_block "$DOCKER_LOGS_ERRORS"
  else
    alert "green" "✓" "Aucune ligne d'erreur/exception détectée dans les logs récents"
  fi
  close_section
}
