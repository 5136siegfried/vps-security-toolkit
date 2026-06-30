#!/usr/bin/env bash
# ================================================================
#  lib/score.sh — Calcul du score global de sécurité.
#  Chaque collector peut appeler `score_penalty <points> <raison>`
#  pour faire baisser le score et enregistrer une issue.
#  À sourcer après avoir sourcé html.sh.
# ================================================================

SCORE=100
SCORE_ISSUES=()

score_penalty() {
  # score_penalty <points> <raison>
  local points="$1" reason="$2"
  SCORE=$(( SCORE - points ))
  SCORE_ISSUES+=("$reason")
}

score_finalize() {
  [[ $SCORE -lt 0 ]] && SCORE=0
  if   [[ $SCORE -ge 80 ]]; then SCORE_COLOR="green"
  elif [[ $SCORE -ge 60 ]]; then SCORE_COLOR="yellow"
  else SCORE_COLOR="red"; fi
}

render_score_section() {
  section "score" "🎯" "Score de securite global"
  ! "${IS_ROOT:-false}" && alert "yellow" "⚠" "Script lance sans root — certains checks sont incomplets. Relancer avec sudo pour un score fiable."
  echo "<div class=\"score-block\">"
  echo "<div class=\"score-num\" style=\"color:var(--${SCORE_COLOR})\">${SCORE}<span style='font-size:24px;color:var(--muted)'>/100</span></div>"
  echo "<div class=\"score-info\">"
  echo "<div class=\"score-label\">Base sur : ressources, SSH, packages, services, integrite, Docker, web</div>"
  if [[ ${#SCORE_ISSUES[@]} -gt 0 ]]; then
    echo "<div class=\"issue-list\">"
    for issue in "${SCORE_ISSUES[@]}"; do
      echo "<span style='color:var(--yellow)'>⚡ ${issue}</span><br>"
    done
    echo "</div>"
  else
    echo "<div style='color:var(--green);font-size:12px'>✓ Aucun probleme critique detecte</div>"
  fi
  echo "</div></div>"
  close_section
}
