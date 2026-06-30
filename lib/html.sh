#!/usr/bin/env bash
# ================================================================
#  lib/html.sh — Helpers de rendu HTML partagés par tous les
#  collectors. À sourcer, jamais à exécuter directement.
# ================================================================

cmd_exists() { command -v "$1" &>/dev/null; }

log() { echo "[ $(basename "${0}") ] $*" >&2; }

html_escape() {
  printf '%s' "$1" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'
}

section() {
  # section <id> <icon> <title> [subtitle]
  local sub=""
  [[ -n "${4:-}" ]] && sub="<span class=\"sec-sub\">${4}</span>"
  echo "<section id=\"${1}\" class=\"collapsible\">"
  echo "<h2 class=\"sec-toggle\" onclick=\"this.parentElement.classList.toggle('collapsed')\">"
  echo "<span class=\"sec-icon\">${2}</span><span class=\"sec-title\">${3}</span>${sub}<span class=\"chevron\">▾</span>"
  echo "</h2>"
  echo "<div class=\"section-body\">"
}

close_section() { echo "</div></section>"; }

table_start() {
  echo "<div class=\"table-wrap\"><table><thead><tr>"
  for col in "$@"; do echo "<th>${col}</th>"; done
  echo "</tr></thead><tbody>"
}
table_end() { echo "</tbody></table></div>"; }

row() {
  echo "<tr>"
  for cell in "$@"; do echo "<td>${cell}</td>"; done
  echo "</tr>"
}

pre_block() {
  # pre_block <content> [max_lines]
  local content="$1" max="${2:-0}"
  if [[ "$max" -gt 0 ]]; then
    content=$(printf '%s' "$content" | head -n "$max")
  fi
  echo "<pre class=\"code-block\">$(html_escape "$content")</pre>"
}

badge() {
  local label="$1" value="$2" color="${3:-gray}"
  echo "<span class=\"badge badge-${color}\"><span class=\"badge-label\">${label}</span><span class=\"badge-val\">${value}</span></span>"
}

status_dot() {
  case "$1" in
    ok)   echo "<span class=\"dot dot-ok\">●</span>" ;;
    warn) echo "<span class=\"dot dot-warn\">●</span>" ;;
    fail) echo "<span class=\"dot dot-fail\">●</span>" ;;
    *)    echo "<span class=\"dot dot-gray\">●</span>" ;;
  esac
}

alert() {
  # alert <red|yellow|green|blue> <icon> <message>
  echo "<div class=\"alert alert-${1}\">${2} ${3}</div>"
}

h3() { echo "<h3 class=\"sub-title\">${1}</h3>"; }

card() {
  # card <label> <value> <color>
  echo "<div class=\"card\"><div class=\"card-label\">${1}</div><div class=\"card-value ${3:-}\">${2}</div></div>"
}

cards_start() { echo "<div class=\"cards\">"; }
cards_end()   { echo "</div>"; }

progress_bar() {
  # progress_bar <label> <value_text> <percent> <color>
  echo "<div class=\"progress-row\"><div class=\"progress-header\"><span>${1}</span><span>${2}</span></div>"
  echo "<div class=\"progress-bar\"><div class=\"progress-fill fill-${4}\" style=\"width:${3}%\"></div></div></div>"
}

pct_color() {
  # pct_color <percent> [warn_threshold=70] [crit_threshold=90]
  local p="$1" w="${2:-70}" c="${3:-90}"
  [[ "$p" =~ ^[0-9]+$ ]] || { echo "gray"; return; }
  if   [[ $p -ge $c ]]; then echo "red"
  elif [[ $p -ge $w ]]; then echo "yellow"
  else echo "green"; fi
}

HTML_HEAD='<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>VPS Security Report</title>
<style>
:root {
  --bg:#0d1117; --surface:#161b22; --surface2:#1c2433;
  --border:#30363d; --text:#e6edf3; --muted:#8b949e;
  --accent:#58a6ff; --green:#3fb950; --yellow:#d29922;
  --red:#f85149; --blue:#58a6ff; --purple:#bc8cff;
  --mono:"JetBrains Mono","Fira Code",ui-monospace,monospace;
  --sans:"Inter",system-ui,-apple-system,sans-serif;
}
*,*::before,*::after{box-sizing:border-box;margin:0;padding:0}
body{font-family:var(--mono);background:var(--bg);color:var(--text);line-height:1.6;font-size:13px}
.report-header{background:var(--surface);border-bottom:1px solid var(--border);padding:20px 28px;display:flex;align-items:center;justify-content:space-between;gap:16px;flex-wrap:wrap}
.logo{display:flex;align-items:center;gap:12px}
.logo-icon{font-size:26px}
.report-header h1{font-family:var(--sans);font-size:17px;font-weight:700;letter-spacing:-.3px}
.host{font-size:11px;color:var(--accent);margin-top:2px}
.meta{text-align:right;font-size:11px;color:var(--muted);line-height:1.9}
.layout{display:flex;min-height:calc(100vh - 72px)}
.sidebar{width:210px;flex-shrink:0;background:var(--surface);border-right:1px solid var(--border);padding:12px 0;position:sticky;top:0;height:100vh;overflow-y:auto}
.sidebar a{display:flex;align-items:center;gap:8px;padding:6px 14px;color:var(--muted);text-decoration:none;font-size:11px;border-left:2px solid transparent;transition:all .15s}
.sidebar a:hover{color:var(--text);background:var(--surface2);border-left-color:var(--accent)}
.nav-group{font-size:9px;color:var(--muted);letter-spacing:.1em;text-transform:uppercase;padding:10px 14px 3px}
.main{flex:1;padding:24px 28px;max-width:1040px}
section{margin-bottom:20px;border:1px solid var(--border);border-radius:8px;overflow:hidden}
.sec-toggle{font-family:var(--sans);font-size:13px;font-weight:600;padding:12px 18px;background:var(--surface);border-bottom:1px solid var(--border);display:flex;align-items:center;gap:9px;cursor:pointer;user-select:none}
.sec-icon{font-size:15px}
.sec-sub{font-size:10px;color:var(--muted);font-weight:400;margin-left:4px}
.chevron{margin-left:auto;color:var(--muted);transition:transform .2s;font-size:11px}
section.collapsed .chevron{transform:rotate(-90deg)}
section.collapsed .sec-toggle{border-bottom:none}
section.collapsed .section-body{display:none}
.section-body{padding:18px}
.sub-title{font-size:10px;color:var(--muted);text-transform:uppercase;letter-spacing:.08em;margin:18px 0 8px;padding-bottom:4px;border-bottom:1px solid var(--border)}
.sub-title:first-child{margin-top:0}
.cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(140px,1fr));gap:10px;margin-bottom:4px}
.card{background:var(--surface2);border:1px solid var(--border);border-radius:6px;padding:14px}
.card-label{font-size:9px;color:var(--muted);text-transform:uppercase;letter-spacing:.08em;margin-bottom:7px}
.card-value{font-size:22px;font-weight:700;font-family:var(--sans);line-height:1}
.card-value.green{color:var(--green)}.card-value.yellow{color:var(--yellow)}.card-value.red{color:var(--red)}.card-value.blue{color:var(--blue)}
.progress-row{margin-bottom:12px}
.progress-header{display:flex;justify-content:space-between;font-size:11px;margin-bottom:4px}
.progress-bar{height:5px;background:var(--border);border-radius:99px;overflow:hidden}
.progress-fill{height:100%;border-radius:99px}
.fill-green{background:var(--green)}.fill-yellow{background:var(--yellow)}.fill-red{background:var(--red)}.fill-gray{background:var(--muted)}
.badge{display:inline-flex;align-items:center;border-radius:4px;overflow:hidden;font-size:11px;margin:2px}
.badge-label{background:var(--surface2);padding:2px 7px;color:var(--muted)}
.badge-val{padding:2px 7px;font-weight:600}
.badge-green .badge-val{background:#1a3a22;color:var(--green)}
.badge-yellow .badge-val{background:#2d2008;color:var(--yellow)}
.badge-red .badge-val{background:#3a1218;color:var(--red)}
.badge-blue .badge-val{background:#0d2340;color:var(--blue)}
.badge-gray .badge-val{background:var(--surface2);color:var(--muted)}
.dot{font-size:10px;margin-right:4px}
.dot-ok{color:var(--green)}.dot-warn{color:var(--yellow)}.dot-fail{color:var(--red)}.dot-gray{color:var(--muted)}
.table-wrap{overflow-x:auto}
table{width:100%;border-collapse:collapse;font-size:11px}
th{background:var(--surface2);color:var(--muted);font-weight:600;font-size:9px;text-transform:uppercase;letter-spacing:.06em;padding:7px 11px;text-align:left;border-bottom:1px solid var(--border)}
td{padding:7px 11px;border-bottom:1px solid var(--border);vertical-align:top}
tr:last-child td{border-bottom:none}
tr:hover td{background:var(--surface2)}
.code-block{background:var(--surface2);border:1px solid var(--border);border-radius:6px;padding:12px 14px;overflow-x:auto;font-size:10.5px;line-height:1.7;white-space:pre-wrap;word-break:break-all;max-height:420px;overflow-y:auto}
.alert{border-radius:6px;padding:10px 14px;font-size:11px;margin-bottom:10px;display:flex;align-items:flex-start;gap:8px}
.alert-red{background:#3a121820;border:1px solid #f8514940;color:var(--red)}
.alert-yellow{background:#2d200820;border:1px solid #d2992240;color:var(--yellow)}
.alert-green{background:#1a3a2220;border:1px solid #3fb95040;color:var(--green)}
.alert-blue{background:#0d234020;border:1px solid #58a6ff40;color:var(--blue)}
.score-block{display:flex;align-items:center;gap:24px;padding:18px;background:var(--surface2);border-radius:6px;margin-bottom:18px}
.score-num{font-size:52px;font-weight:800;font-family:var(--sans);line-height:1}
.score-info{flex:1}
.score-label{font-size:11px;color:var(--muted);margin-bottom:8px}
.issue-list{font-size:11px;line-height:2}
.not-root-warn{background:#2d200820;border:1px solid #d2992240;color:var(--yellow);padding:8px 14px;border-radius:6px;font-size:11px;margin-bottom:16px}
.tag{font-size:10px;padding:2px 8px;border-radius:99px;border:1px solid var(--border);color:var(--muted);margin-right:4px}
footer{text-align:center;padding:18px;color:var(--border);font-size:10px;border-top:1px solid var(--border)}
@media(max-width:700px){.sidebar{display:none}.main{padding:14px}.cards{grid-template-columns:1fr 1fr}}
</style>
</head>
<body>'

HTML_NAV='<nav class="sidebar">
  <div class="nav-group">Vue d ensemble</div>
  <a href="#score">Score global</a>
  <div class="nav-group">Systeme</div>
  <a href="#system">Systeme</a>
  <a href="#cpu">CPU</a>
  <a href="#ram">RAM</a>
  <a href="#disk">Disque</a>
  <a href="#procs">Processus</a>
  <div class="nav-group">Reseau</div>
  <a href="#network">Reseau</a>
  <a href="#netadv">Reseau avance</a>
  <div class="nav-group">Acces</div>
  <a href="#auth">SSH Auth</a>
  <a href="#sshcfg">Config SSH</a>
  <a href="#users">Utilisateurs</a>
  <a href="#certs">Certificats</a>
  <div class="nav-group">Services</div>
  <a href="#services">Systemd</a>
  <a href="#cron">Cron</a>
  <a href="#docker">Docker</a>
  <a href="#dockerlogs">Docker logs</a>
  <div class="nav-group">Web</div>
  <a href="#nginx">Nginx attaques</a>
  <div class="nav-group">Securite</div>
  <a href="#kernel">Kernel params</a>
  <a href="#fail2ban">fail2ban</a>
  <a href="#lynis">Lynis</a>
  <a href="#rootkits">Rootkits</a>
  <a href="#integrity">Integrite</a>
  <a href="#suid">SUID/SGID</a>
  <a href="#secrets">Secrets</a>
  <a href="#trivy">Trivy CVE</a>
  <a href="#pkgs">Packages</a>
  <div class="nav-group">Audit</div>
  <a href="#history">Historique</a>
</nav>
<main class="main">'

HTML_FOOT='</main>
</div>
<footer>vps-security-toolkit — rapport genere localement, aucune donnee transmise hors webhook/mail configures</footer>
<script>
document.querySelectorAll("section.collapsible").forEach(s => {
  // Ouvre par défaut sauf si déjà collapsed côté serveur
});
</script>
</body>
</html>'
