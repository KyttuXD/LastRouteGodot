#!/usr/bin/env bash
# Open ONLY the Godot 2 game ports. Dry run by default; needs KT's explicit OK before --apply.
#   deploy/firewall.sh           print the commands for the firewall found on this host
#   deploy/firewall.sh --apply   run them (root)
# Ports: TCP 8105 (HTTP room directory/updates/accounts), UDP 1105 (authenticated gameplay relay).
# Nothing else is opened, closed or reset; existing rules (website 80/443, SSH, Minecraft) stay as they are.
set -euo pipefail
APPLY=0; [ "${1:-}" = "--apply" ] && APPLY=1
TCP_PORT="${LASTROUTE_HTTP_PORT:-8105}"; UDP_PORT="${LASTROUTE_RELAY_PORT:-1105}"
if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
  CMDS=("ufw allow $TCP_PORT/tcp comment 'lastroute-godot2 http'" "ufw allow $UDP_PORT/udp comment 'lastroute-godot2 relay'")
  KIND=ufw
elif command -v iptables >/dev/null 2>&1 && ! { iptables -S 2>/dev/null | grep -q '^-P INPUT ACCEPT' && [ "$(iptables -S 2>/dev/null | grep -c '^-A INPUT')" = 0 ]; }; then
  CMDS=("iptables -C INPUT -p tcp --dport $TCP_PORT -j ACCEPT 2>/dev/null || iptables -I INPUT -p tcp --dport $TCP_PORT -m comment --comment lastroute-godot2 -j ACCEPT"
        "iptables -C INPUT -p udp --dport $UDP_PORT -j ACCEPT 2>/dev/null || iptables -I INPUT -p udp --dport $UDP_PORT -m comment --comment lastroute-godot2 -j ACCEPT"
        "# persist (Debian/Ubuntu): netfilter-persistent save")
  KIND=iptables
elif command -v iptables >/dev/null 2>&1; then
  echo "ufw is inactive and iptables has policy ACCEPT with no INPUT rules: no host firewall rule is needed."
  echo "Check the provider's cloud firewall (panel) allows TCP $TCP_PORT and UDP $UDP_PORT."; exit 0
else
  echo "no ufw or iptables found; open TCP $TCP_PORT and UDP $UDP_PORT in the provider firewall panel instead"; exit 0
fi
echo "firewall: $KIND (apply=$APPLY)"
for c in "${CMDS[@]}"; do
  if [ "$APPLY" = 1 ]; then case "$c" in \#*) echo "$c" ;; *) echo "+ $c"; bash -c "$c" ;; esac; else echo "WOULD: $c"; fi
done
echo "Also check the VPS provider's cloud firewall (if any) allows TCP $TCP_PORT and UDP $UDP_PORT."
