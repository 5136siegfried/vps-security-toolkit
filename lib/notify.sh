#!/usr/bin/env bash
# ================================================================
#  lib/notify.sh — Notification webhook (Discord/Slack) et/ou mail.
#  Déclenché par run.sh si score < seuil ou anomalie critique.
#
#  Config via variables d'environnement (secrets CI ou .env local) :
#    NOTIFY_WEBHOOK_URL    — URL webhook Discord ou Slack (optionnel)
#    NOTIFY_WEBHOOK_TYPE   — "discord" ou "slack" (défaut: discord)
#    NOTIFY_MAIL_TO        — adresse destinataire (optionnel)
#    NOTIFY_MAIL_FROM      — adresse expéditeur (défaut: vps-audit@<hostname>)
#    NOTIFY_SCORE_THRESHOLD— seuil sous lequel on notifie (défaut: 70)
#    SMTP_SERVER, SMTP_PORT, SMTP_USER, SMTP_PASS — si mail via msmtp/sendmail custom
# ================================================================

NOTIFY_SCORE_THRESHOLD="${NOTIFY_SCORE_THRESHOLD:-70}"
NOTIFY_WEBHOOK_TYPE="${NOTIFY_WEBHOOK_TYPE:-discord}"

notify_should_fire() {
  # notify_should_fire <score>
  local score="$1"
  [[ "$score" -lt "$NOTIFY_SCORE_THRESHOLD" ]]
}

notify_build_summary() {
  # notify_build_summary <score> <hostname> <issues_array_name>
  local score="$1" host="$2"
  shift 2
  local issues=("$@")
  local txt="🛡 Audit VPS — ${host}\nScore : ${score}/100\n"
  if [[ ${#issues[@]} -gt 0 ]]; then
    txt+="\nPoints d'attention :\n"
    for i in "${issues[@]}"; do
      txt+="• ${i}\n"
    done
  fi
  printf '%b' "$txt"
}

notify_webhook() {
  # notify_webhook <message_text> <report_url_optional>
  [[ -z "${NOTIFY_WEBHOOK_URL:-}" ]] && { log "Webhook non configuré, skip"; return 0; }
  local message="$1" report_url="${2:-}"
  local payload

  if [[ "$NOTIFY_WEBHOOK_TYPE" == "slack" ]]; then
    local full_text="$message"
    [[ -n "$report_url" ]] && full_text+="\n<${report_url}|Voir le rapport complet>"
    payload=$(jq -n --arg text "$full_text" '{text: $text}' 2>/dev/null || \
      echo "{\"text\": \"$(echo "$message" | sed 's/"/\\"/g')\"}")
  else
    # Discord
    local full_desc="$message"
    [[ -n "$report_url" ]] && full_desc+="\n\n[Voir le rapport complet](${report_url})"
    payload=$(jq -n --arg content "$full_desc" '{content: $content}' 2>/dev/null || \
      echo "{\"content\": \"$(echo "$message" | sed 's/"/\\"/g')\"}")
  fi

  curl -sf -X POST -H "Content-Type: application/json" \
    -d "$payload" "$NOTIFY_WEBHOOK_URL" >/dev/null \
    && log "Webhook envoyé" \
    || log "⚠ Échec envoi webhook"
}

notify_mail() {
  # notify_mail <subject> <body> <attachment_path_optional>
  [[ -z "${NOTIFY_MAIL_TO:-}" ]] && { log "Mail non configuré, skip"; return 0; }
  local subject="$1" body="$2" attachment="${3:-}"
  local from="${NOTIFY_MAIL_FROM:-vps-audit@$(hostname -f 2>/dev/null || hostname)}"

  if cmd_exists mail; then
    if [[ -n "$attachment" && -f "$attachment" ]]; then
      if mail -V &>/dev/null && echo | mail -A "$attachment" -s "x" root &>/dev/null; then
        echo "$body" | mail -s "$subject" -r "$from" -A "$attachment" "$NOTIFY_MAIL_TO"
      else
        # mailutils ne supporte pas -A de la même façon, fallback sans pièce jointe
        echo "$body" | mail -s "$subject" -r "$from" "$NOTIFY_MAIL_TO"
      fi
    else
      echo "$body" | mail -s "$subject" -r "$from" "$NOTIFY_MAIL_TO"
    fi
    log "Mail envoyé à $NOTIFY_MAIL_TO"
  elif cmd_exists sendmail; then
    {
      echo "From: $from"
      echo "To: $NOTIFY_MAIL_TO"
      echo "Subject: $subject"
      echo ""
      echo "$body"
    } | sendmail -t
    log "Mail envoyé via sendmail à $NOTIFY_MAIL_TO"
  else
    log "⚠ Aucun MTA disponible (mail/sendmail) — mail non envoyé"
  fi
}

notify_dispatch() {
  # notify_dispatch <score> <hostname> <report_url> issue1 issue2 ...
  local score="$1" host="$2" report_url="$3"
  shift 3
  local issues=("$@")

  if ! notify_should_fire "$score"; then
    log "Score ${score} >= seuil ${NOTIFY_SCORE_THRESHOLD}, pas de notification"
    return 0
  fi

  local summary
  summary=$(notify_build_summary "$score" "$host" "${issues[@]}")

  notify_webhook "$summary" "$report_url"
  notify_mail "🛡 Audit VPS ${host} — Score ${score}/100" "$summary" ""
}
