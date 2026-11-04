#!/usr/bin/env bash
# Proves the happy path. Run after scripts/provision.sh.
cd "$(dirname "$0")"; . ./lib.sh

echo "--- tunnel"
x a-fw "wg show wg0 latest-handshakes" | awk '{ if ($2>0) f=1 } END{exit !f}' && ok "WireGuard handshake completed" || bad "WireGuard handshake completed"
expect_ok "a-fw reaches b-gw over tunnel (203.0.113.10)" a-fw "ping -c1 -W2 203.0.113.10"

echo "--- zone policy (expected ALLOW)"
expect_ok "DMZ web  -> APP 8080"  a-web  "nc -zw2 192.0.2.74 8080"
expect_ok "APP      -> DB  5432"  a-app  "nc -zw2 192.0.2.138 5432"
expect_ok "MGMT     -> DMZ 22"    a-mgmt "nc -zw2 192.0.2.10 22"
expect_ok "MGMT     -> DB  22"    a-mgmt "nc -zw2 192.0.2.138 22"
expect_ok "MGMT     -> DB  ping"  a-mgmt "ping -c1 -W2 192.0.2.138"

echo "--- zone policy (expected DENY)"
expect_fail "DMZ web -> DB  5432" a-web  "nc -zw2 192.0.2.138 5432"
expect_fail "DMZ web -> APP 22"   a-web  "nc -zw2 192.0.2.74 22"
expect_fail "DB      -> APP 8080" a-db   "nc -zw2 192.0.2.74 8080"
expect_fail "APP     -> DMZ 22"   a-app  "nc -zw2 192.0.2.10 22"
for h in a-web a-app a-db a-mgmt; do
  expect_fail "$h cannot reach the collector directly" $h "nc -zw2 198.51.100.10 514"
done

echo "--- nothing exposed / nothing leaks"
expect_fail "ISP has no route to Site A zones" isp "ip route get 192.0.2.10"
expect_fail "ISP has no route to Site B LAN"   isp "ip route get 198.51.100.10"
expect_fail "ISP cannot reach collector"       isp "nc -zw2 198.51.100.10 514"
expect_fail "ISP cannot reach a-fw services"   isp "nc -zw2 203.0.113.2 22"
x isp "rm -f /tmp/u.pcap; (timeout 12 tcpdump -ni eth1 -w /tmp/u.pcap >/dev/null 2>&1 &)"; sleep 1
fire 5001; wait_for 5001 3 20 && ok "firewall log lines arrive at collector" || bad "firewall log lines arrive at collector"
sleep 11
NONWG=$(x isp "tcpdump -nr /tmp/u.pcap 'not udp port 51820' 2>/dev/null | wc -l")
[ "${NONWG//[[:space:]]/}" = "0" ] && ok "underlay carried only UDP/51820" || bad "underlay carried non-WireGuard traffic ($NONWG pkts)"
PLAIN=$(x isp "tcpdump -nAr /tmp/u.pcap 2>/dev/null | grep -c 'A-FW'")
[ "${PLAIN//[[:space:]]/}" = "0" ] && ok "no plaintext log content on underlay" || bad "plaintext log content visible on underlay"
summary
