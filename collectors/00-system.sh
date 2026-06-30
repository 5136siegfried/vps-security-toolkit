#!/usr/bin/env bash
# ================================================================
#  collectors/00-system.sh — CPU, RAM, Disque, Processus
# ================================================================

collect_system() {
  log "Système..."
  UPTIME_RAW=$(uptime -p 2>/dev/null || uptime)
  LOAD_RAW=$(uptime | awk -F'load average:' '{print $2}' | xargs)
  KERNEL=$(uname -r)
  OS_PRETTY=$(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d'"' -f2 || uname -s)
  ARCH=$(uname -m)
  PROC_COUNT=$(nproc)
  if cmd_exists apt; then
    apt-get -qq update 2>/dev/null || true
    PKG_UPDATES=$(apt list --upgradable 2>/dev/null | grep -vc 'Listing' || echo "?")
    SEC_UPDATES=$(apt list --upgradable 2>/dev/null | { grep -ic 'security' || true; })
  else
    PKG_UPDATES="N/A"; SEC_UPDATES="N/A"
  fi
}

collect_cpu() {
  log "CPU..."
  CPU_MODEL=$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d':' -f2 | xargs || echo "N/A")
  CPU_CORES=$(grep -c '^processor' /proc/cpuinfo 2>/dev/null || echo "?")
  if [[ -f /proc/stat ]]; then
    read -r _ u n s id wa _ < <(grep '^cpu ' /proc/stat)
    sleep 1
    read -r _ u2 n2 s2 id2 wa2 _ < <(grep '^cpu ' /proc/stat)
    total_delta=$(( (u2+n2+s2+id2+wa2) - (u+n+s+id+wa) ))
    idle_delta=$(( id2-id ))
    [[ $total_delta -gt 0 ]] && CPU_USAGE=$(( (total_delta-idle_delta)*100/total_delta )) || CPU_USAGE=0
  else
    CPU_USAGE="?"
  fi
  CPU_COLOR=$(pct_color "$CPU_USAGE")
}

collect_ram() {
  log "RAM..."
  MEM_TOTAL_KB=$(awk '/^MemTotal/{print $2}' /proc/meminfo)
  MEM_AVAIL_KB=$(awk '/^MemAvailable/{print $2}' /proc/meminfo)
  MEM_TOTAL_MB=$((MEM_TOTAL_KB/1024))
  MEM_USED_MB=$(( (MEM_TOTAL_KB-MEM_AVAIL_KB)/1024 ))
  MEM_PCT=$(( MEM_USED_MB*100/MEM_TOTAL_MB ))
  SWAP_TOTAL=$(awk '/^SwapTotal/{print $2}' /proc/meminfo)
  SWAP_FREE=$(awk '/^SwapFree/{print $2}' /proc/meminfo)
  if [[ $SWAP_TOTAL -gt 0 ]]; then
    SWAP_USED=$(( (SWAP_TOTAL-SWAP_FREE)/1024 ))
    SWAP_TOTAL_MB=$((SWAP_TOTAL/1024))
    SWAP_PCT=$(( SWAP_USED*100/SWAP_TOTAL_MB ))
  else
    SWAP_USED=0; SWAP_TOTAL_MB=0; SWAP_PCT=0
  fi
  MEM_COLOR=$(pct_color "$MEM_PCT")
}

collect_disk() {
  log "Disque..."
  DISK_RAW=$(df -h --output=source,fstype,size,used,avail,pcent,target 2>/dev/null \
    | grep -vE 'tmpfs|devtmpfs|udev|squashfs' | tail -n +2 || df -h | tail -n +2)
  TOP_DIRS=$( { du -xhS / 2>/dev/null || true; } | sort -rh | head -10 )
  if [[ -z "$TOP_DIRS" ]]; then
    TOP_DIRS=$( { du -hS /var /home /opt /root /tmp 2>/dev/null || true; } | sort -rh | head -10 )
  fi
  INODE_RAW=$(df -i 2>/dev/null | grep -vE 'tmpfs|devtmpfs|udev|squashfs' | tail -n +2 || echo "N/A")
}

collect_processes() {
  log "Processus..."
  PROC_TOP=$(ps aux --sort=-%cpu 2>/dev/null | head -15 || ps aux 2>/dev/null | head -15 || echo "N/A")
  if cmd_exists lsof; then
    OPEN_FILES_COUNT=$(lsof 2>/dev/null | wc -l || echo "N/A")
    OPEN_PORTS=$(lsof -i -n -P 2>/dev/null | grep LISTEN | head -20 || echo "N/A")
  else
    OPEN_FILES_COUNT="lsof non disponible"
    OPEN_PORTS="lsof non disponible"
  fi
}

render_system_section() {
  section "system" "⚙" "Système"
  cards_start
  card "OS" "$OS_PRETTY" ""
  card "Uptime" "$UPTIME_RAW" ""
  card "Load Average" "$LOAD_RAW" ""
  card "vCPU" "$PROC_COUNT" "blue"
  cards_end
  close_section
}

render_cpu_section() {
  section "cpu" "🔲" "CPU"
  echo "<p style='font-size:11px;color:var(--muted);margin-bottom:14px'>${CPU_MODEL} — ${CPU_CORES} core(s)</p>"
  progress_bar "Utilisation" "${CPU_USAGE}%" "$CPU_USAGE" "$CPU_COLOR"
  [[ "$CPU_USAGE" =~ ^[0-9]+$ && "$CPU_USAGE" -ge 90 ]] && score_penalty 10 "CPU critique (${CPU_USAGE}%)"
  close_section
}

render_ram_section() {
  section "ram" "💾" "RAM / Swap"
  progress_bar "RAM" "${MEM_USED_MB} / ${MEM_TOTAL_MB} MB (${MEM_PCT}%)" "$MEM_PCT" "$MEM_COLOR"
  if [[ $SWAP_TOTAL_MB -gt 0 ]]; then
    progress_bar "Swap" "${SWAP_USED} / ${SWAP_TOTAL_MB} MB (${SWAP_PCT}%)" "$SWAP_PCT" "$(pct_color "$SWAP_PCT" 40 70)"
  else
    progress_bar "Swap" "Non configuré" "0" "gray"
  fi
  [[ $MEM_PCT -ge 90 ]] && score_penalty 10 "RAM critique (${MEM_PCT}%)"
  [[ $MEM_PCT -ge 70 && $MEM_PCT -lt 90 ]] && score_penalty 5 "RAM élevée (${MEM_PCT}%)"
  close_section
}

render_disk_section() {
  section "disk" "💿" "Disque"
  h3 "Systèmes de fichiers"
  table_start "Source" "Type" "Taille" "Utilisé" "Libre" "%" "Monté sur"
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    read -r src fstype size used avail pct target <<< "$line"
    local pn="${pct//%/}"
    local color
    color=$(pct_color "$pn" 75 90)
    local pc="<span style='color:var(--${color})'>${pct}</span>"
    [[ "$color" != "green" ]] && pc="<span style='color:var(--${color});font-weight:700'>${pct}</span>"
    row "$src" "$fstype" "$size" "$used" "$avail" "$pc" "$target"
    [[ "$pn" =~ ^[0-9]+$ && "$pn" -ge 90 ]] && score_penalty 10 "Disque plein sur ${target} (${pct})"
  done <<< "$DISK_RAW"
  table_end
  h3 "Top 10 dossiers volumineux"
  table_start "Taille" "Chemin"
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    row "$(echo "$line" | awk '{print $1}')" "$(echo "$line" | awk '{print $2}')"
  done <<< "$TOP_DIRS"
  table_end
  h3 "Inodes"
  pre_block "$INODE_RAW"
  close_section
}

render_processes_section() {
  section "procs" "🔄" "Processus"
  h3 "Top processus (CPU)"
  pre_block "$PROC_TOP"
  echo "$(badge "Fichiers ouverts" "${OPEN_FILES_COUNT}" "blue")"
  h3 "Ports ouverts (lsof)"
  pre_block "$OPEN_PORTS"
  close_section
}

render_pkgs_section() {
  section "pkgs" "📦" "Packages &amp; Mises à jour"
  cards_start
  card "Packages upgradables" "$PKG_UPDATES" "$([ "$PKG_UPDATES" != "0" ] && echo yellow || echo green)"
  card "Mises à jour sécurité" "$SEC_UPDATES" "$([ "$SEC_UPDATES" != "0" ] && echo red || echo green)"
  cards_end
  if [[ "$SEC_UPDATES" =~ ^[0-9]+$ && "$SEC_UPDATES" -gt 0 ]]; then
    score_penalty 10 "${SEC_UPDATES} mises à jour sécurité en attente"
    alert "yellow" "⚡" "Mises à jour de sécurité disponibles : <code>apt upgrade</code>"
  fi
  close_section
}
