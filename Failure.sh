#!/usr/bin/env bash
# Proves failure behaviour. Run after verify.sh passes.
cd "$(dirname "$0")"; . ./lib.sh

echo "=== F1: underlay outage (ISP stops passing WireGuard) ==="
fire 5101; wait_for 5101 3 20 && ok "baseline delivery works" || bad "baseline delivery works"
x isp "nft flush chain inet isp forward"            # policy drop => black hole
fire 5102; sleep 10
[ "$(collected 5102)" -eq 0 ] && ok "during outage: nothing delivered" || bad "during outage: something was delivered"
expect_fail "during outage: no clear-text fallback path to collector" a-fw "nc -zw2 198.51.100.10 514"
x isp "nft -f /tmp/fw.nft"                          # restore
wait_for 5102 3 60 && ok "after restore: buffered events replayed (count=$(collected 5102))" || bad "after restore: buffered events replayed"

echo "=== F2: tunnel interface down on a-fw (fail closed) ==="
x a-fw "ip link set wg0 down"
fire 5201
expect_fail "wg0 down: collector unreachable (no route, no leak)" a-fw "nc -zw2 198.51.100.10 514"
x isp "rm -f /tmp/f2.pcap; (timeout 8 tcpdump -ni eth1 -w /tmp/f2.pcap 'not udp port 51820' >/dev/null 2>&1 &)"; sleep 9
N=$(x isp "tcpdump -nr /tmp/f2.pcap 2>/dev/null | wc -l")
[ "${N//[[:space:]]/}" = "0" ] && ok "wg0 down: zero non-WireGuard packets on underlay" || bad "wg0 down: $N non-WireGuard packets leaked"
# Lesson: taking wg0 down also deletes the static route to Site B; restore must re-add it.
x a-fw "ip link set wg0 up && ip route replace 198.51.100.0/24 dev wg0 src 203.0.113.9"
wait_for 5201 3 60 && ok "wg0 restored: backlog delivered" || bad "wg0 restored: backlog delivered"

echo "=== F3: collector down ==="
x b-collector "kill \$(cat /run/rsyslogd.pid)"
fire 5301; sleep 8
x b-collector "rsyslogd -f /etc/rsyslog-collector.conf -i /run/rsyslogd.pid"
wait_for 5301 3 60 && ok "collector back: backlog delivered" || bad "collector back: backlog delivered"
echo "note: TCP syslog is at-least-once; duplicates after replay are possible (see README)."
summary
