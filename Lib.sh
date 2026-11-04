P=clab-bank; PASS=0; FAIL=0
x()  { local n=$1; shift; docker exec "$P-$n" sh -c "$*"; }
ok()  { echo "PASS  $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL  $1"; FAIL=$((FAIL+1)); }
expect_ok()   { if x "$2" "$3" >/dev/null 2>&1; then ok "$1"; else bad "$1"; fi; }
expect_fail() { if x "$2" "$3" >/dev/null 2>&1; then bad "$1"; else ok "$1"; fi; }
# a-web -> a-db on an unlisted port is dropped AND logged by a-fw; the port is the marker.
fire()      { for _ in 1 2 3; do x a-web "nc -zw1 192.0.2.138 $1" >/dev/null 2>&1 || true; done; }
collected() { x b-collector "cat /var/log/remote/* 2>/dev/null | grep -c 'DPT=$1'" 2>/dev/null || echo 0; }
wait_for()  { local port=$1 want=$2 t=${3:-30}; while [ "$t" -gt 0 ]; do
                [ "$(collected "$port")" -ge "$want" ] && return 0; sleep 1; t=$((t-1)); done; return 1; }
summary()   { echo; echo "$PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]; }
