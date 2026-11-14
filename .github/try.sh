#!/bin/sh
# Tries the package build.sh left in dist/, as a server would have it.
# Runs INSIDE a NEW debian:13 container - one with no compiler and
# nothing of the build in it:
#
#   docker run --rm --cap-add NET_RAW --cap-add SYS_NICE \
#       --cap-add NET_ADMIN -e PINGER_FULL_BUFFER=1 \
#       -v "$PWD:/src:ro" -w /src debian:13 sh .github/try.sh
#
# (NET_RAW: the raw ICMP socket. SYS_NICE: pingerd raises its own
# priority when it starts. NET_ADMIN: the socket's receive buffer is
# forced past net.core.rmem_max, as it is for root on a server -
# PINGER_FULL_BUFFER=1 demands that it was, and that pingerd did not
# warn about a short one. Leave both out where NET_ADMIN cannot be
# had, as in a rootless container.)
#
# The package installs with apt, which fetches what it depends on; the
# module pings 127.0.0.1; pingerd, started as the unit starts it, reads
# its hosts from the plan's database and answers on its web port with
# what it measured, as "nobody"; with --site it measures that site's
# hosts only; and the package can be removed again.
set -eu

export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get install -y -q --no-install-recommends \
    ./dist/pinger_*_"$(dpkg --print-architecture)".deb
dpkg -s pinger | grep -E '^(Status|Version|Depends):'
if command -v gcc >/dev/null 2>&1; then
    echo "there is a compiler here: this is not a machine with only the package"
    exit 1
fi

# 1. the installed module pings
python3 -B tests/loopback.py

# 2. pingerd. A plan with two sites; every address in it is this
#    machine's own (all of 127/8 answers).
python3 - <<'EOF'
import sqlite3
db = sqlite3.connect('/etc/ipplan.db')
db.execute('CREATE TABLE network (node_id INTEGER, name TEXT)')
db.execute('CREATE TABLE host (node_id INTEGER, name TEXT, '
           'ipv4_addr_txt TEXT, network_id INTEGER)')
db.execute("INSERT INTO network VALUES (1, 'HERE@SERVERS')")
db.execute("INSERT INTO network VALUES (2, 'THERE@SERVERS')")
db.execute("INSERT INTO host VALUES (11, 'a.here.test', '127.0.0.1', 1)")
db.execute("INSERT INTO host VALUES (12, 'b.there.test', '127.0.0.2', 2)")
db.execute("INSERT INTO host VALUES (13, 'no-address.here.test', NULL, 1)")
db.commit()
EOF
cp /etc/ipplan.db /tmp/plan.db
grep -xF 'ExecStart=/usr/sbin/pingerd' /usr/lib/systemd/system/pingerd.service

# as the unit starts it - no switches: every host of the plan
/usr/sbin/pingerd --port 13110 --interval 0.5 > /tmp/pingerd.log 2>&1 &
daemon=$!
stop() { kill "$daemon" 2>/dev/null || true; }
python3 -B tests/measured.py 13110 \
    --counted a.here.test b.there.test \
    --never no-address.here.test || { stop; cat /tmp/pingerd.log; exit 1; }
head -5 /tmp/pingerd.log
if [ "${PINGER_FULL_BUFFER:-}" = 1 ] && grep WARNING /tmp/pingerd.log; then
    echo "pingerd warns about its receive buffer where it could force it"
    stop
    exit 1
fi
# it gave up root once the socket was open
uid=$(awk '/^Uid:/ {print $2}' "/proc/$daemon/status")
echo "pingerd runs as uid $uid (nobody is $(id -u nobody))"
test "$uid" = "$(id -u nobody)" || { stop; exit 1; }
stop

# one site only, from a database named on the command line
/usr/sbin/pingerd --port 13111 --interval 0.5 \
    --database /tmp/plan.db --site here &
daemon=$!
python3 -B tests/measured.py 13111 \
    --counted a.here.test \
    --never b.there.test no-address.here.test || { stop; exit 1; }
stop

# 3. and it goes away again
apt-get remove -y -q pinger
test ! -e /usr/sbin/pingerd
test ! -e /usr/lib/systemd/system/pingerd.service
echo "ok: the package installs, runs and is removed"
