#!/usr/bin/env bash
# ================================================================
#  collectors/01-network.sh — Réseau, firewall, connexions
# ================================================================

collect_network() {
  log "Réseau..."
  NET_IFACES=$(ip -br addr show 2>/dev/null || ifconfig -a 2>/dev/null || echo "N/A")
  NET_ESTABLISHED=$(ss -tnp 2>/dev/null | grep ESTAB || netstat -tnp 2>/dev/null | grep ESTABLISHED || echo "N/A")
  NET_LISTEN=$(ss -tlnup 2>/dev/null || netstat -tlnup 2>/dev/null || echo "N/A")
  NET_OUTBOUND=$(ss -tnp 2>/dev/null | grep ESTAB \
    | grep -vE '127\.|10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.' \
    | head -20 || echo "")
  if cmd_exists ufw; then
    FW_STATUS=$(ufw status verbose 2>/dev/null | head -30); FW_TOOL="ufw"
  elif cmd_exists iptables; then
    FW_STATUS=$(iptables -L -n --line-numbers 2>/dev/null | head -50); FW_TOOL="iptables"
  elif cmd_exists nft; then
    FW_STATUS=$(nft list ruleset 2>/dev/null | head -40); FW_TOOL="nftables"
  else
    FW_STATUS="Aucun outil firewall détecté"; FW_TOOL="unknown"
  fi
}

collect_network_advanced() {
  log "Réseau avancé..."
  NET_STATE_COUNT=$(ss -tan 2>/dev/null | awk '{print $1}' | sort | uniq -c | sort -rn || echo "N/A")
  ARP_TABLE=$(arp -n 2>/dev/null || ip neigh show 2>/dev/null || echo "N/A")
  ROUTES=$(ip route show 2>/dev/null || route -n 2>/dev/null || echo "N/A")
  DNS_CONFIG=$(cat /etc/resolv.conf 2>/dev/null || echo "N/A")
}

render_network_section() {
  section "network" "🌐" "Réseau"
  h3 "Interfaces"
  pre_block "$NET_IFACES"
  h3 "Ports en écoute"
  pre_block "$NET_LISTEN"
  h3 "Connexions établies"
  pre_block "$NET_ESTABLISHED"
  h3 "Firewall (${FW_TOOL})"
  pre_block "$FW_STATUS"
  close_section
}

render_network_advanced_section() {
  section "netadv" "📡" "Réseau avancé"
  if [[ -n "${NET_OUTBOUND:-}" ]]; then
    alert "yellow" "⚡" "Connexions sortantes vers IPs publiques (hors RFC1918) :"
    pre_block "$NET_OUTBOUND"
    score_penalty 5 "Connexions sortantes vers IPs publiques détectées"
  else
    alert "green" "✓" "Aucune connexion sortante suspecte détectée"
  fi
  h3 "États de connexions"
  pre_block "$NET_STATE_COUNT"
  h3 "Table ARP"
  pre_block "$ARP_TABLE"
  h3 "Routes"
  pre_block "$ROUTES"
  h3 "DNS (/etc/resolv.conf)"
  pre_block "$DNS_CONFIG"
  close_section
}
