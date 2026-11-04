#!/usr/bin/env bash
# Configures an already-deployed containerlab topology. Keys are generated
# in-memory and never written to disk or the repo.
set -euo pipefail
cd "$(dirname "$0")/.."
P=clab-bank
x()   { local n=$1; shift; docker exec "$P-$n" sh -c "$*"; }
xi()  { local n=$1; shift; docker exec -i "$P-$n" sh -c "$*"; }
put() { docker cp "$2" "$P-$1:$3"; }
ip_up() { x "$1" "ip addr add $3 dev $2 && ip link set $2 up"; }
listen() { docker exec -d "$P-$1" nc -lk "$2"; }

echo "== strip containerlab's management default route (out-of-band plumbing, not part of the design)"
for n in isp a-fw a-web a-app a-db a-mgmt b-gw b-collector; do
  x $n "ip route del default 2>/dev/null || true"
done
for n in isp a-fw b-gw; do x $n "sysctl -qw net.ipv4.ip_forward=1"; done

echo "== addressing"
ip_up isp eth1 203.0.113.1/30;  ip_up a-fw eth1 203.0.113.2/30
ip_up isp eth2 203.0.113.5/30;  ip_up b-gw eth1 203.0.113.6/30
ip_up a-fw eth2 192.0.2.1/26;   ip_up a-web  eth1 192.0.2.10/26
ip_up a-fw eth3 192.0.2.65/26;  ip_up a-app  eth1 192.0.2.74/26
ip_up a-fw eth4 192.0.2.129/26; ip_up a-db   eth1 192.0.2.138/26
ip_up a-fw eth5 192.0.2.193/26; ip_up a-mgmt eth1 192.0.2.202/26
ip_up b-gw eth2 198.51.100.1/24; ip_up b-collector eth1 198.51.100.10/24
x a-web  "ip route add default via 192.0.2.1"
x a-app  "ip route add default via 192.0.2.65"
x a-db   "ip route add default via 192.0.2.129"
x a-mgmt "ip route add default via 192.0.2.193"
x b-collector "ip route add default via 198.51.100.1"
x a-fw "ip route add 203.0.113.4/30 via 203.0.113.1"
x b-gw "ip route add 203.0.113.0/30 via 203.0.113.5"

echo "== WireGuard (kernel module if present, else wireguard-go)"
A_KEY=$(x a-fw "wg genkey"); B_KEY=$(x b-gw "wg genkey")
A_PUB=$(echo "$A_KEY" | xi a-fw "wg pubkey"); B_PUB=$(echo "$B_KEY" | xi b-gw "wg pubkey")
wg_up() { # node tunnel-addr privkey peer-pub endpoint allowed-ips
  x "$1" "ip link add wg0 type wireguard 2>/dev/null || wireguard-go wg0"
  echo "$3" | xi "$1" "wg set wg0 listen-port 51820 private-key /dev/stdin peer $4 endpoint $5 allowed-ips $6 persistent-keepalive 15"
  x "$1" "ip addr add $2 dev wg0 && ip link set wg0 up"
}
wg_up a-fw 203.0.113.9/30  "$A_KEY" "$B_PUB" 203.0.113.6:51820 198.51.100.0/24,203.0.113.10/32
wg_up b-gw 203.0.113.10/30 "$B_KEY" "$A_PUB" 203.0.113.2:51820 192.0.2.0/24,203.0.113.9/32
unset A_KEY B_KEY
x a-fw "ip route add 198.51.100.0/24 dev wg0 src 203.0.113.9"
x b-gw "ip route add 192.0.2.0/24 dev wg0"

echo "== firewalls"
for n in isp a-fw b-gw; do put $n configs/$n.nft /tmp/fw.nft; x $n "nft -f /tmp/fw.nft"; done

echo "== test listeners in zones"
listen a-web 22; listen a-app 8080; listen a-app 22; listen a-db 5432; listen a-db 22

echo "== log pipeline: nflog -> ulogd -> rsyslog -> tunnel -> collector"
x b-collector "mkdir -p /var/log/remote /var/spool/rsyslog"
put b-collector configs/rsyslog-collector.conf /etc/rsyslog-collector.conf
x b-collector "rsyslogd -f /etc/rsyslog-collector.conf -i /run/rsyslogd.pid"
LIB=$(x a-fw 'ls -d /usr/lib/*/ulogd')
sed "s#@LIB@#$LIB#g" configs/ulogd.conf > /tmp/ulogd.conf
x a-fw "mkdir -p /var/log/ulog /var/spool/rsyslog && touch /var/log/ulog/fw.log"
put a-fw /tmp/ulogd.conf /etc/ulogd.conf
x a-fw "ulogd -d -c /etc/ulogd.conf"
put a-fw configs/rsyslog-a-fw.conf /etc/rsyslog-fw.conf
x a-fw "rsyslogd -f /etc/rsyslog-fw.conf -i /run/rsyslogd.pid"
echo "provisioned."