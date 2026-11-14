#!/bin/sh
# Tries the package build.sh left in dist/, as a server would have it.
# Runs INSIDE a NEW debian:13 container - one with no compiler and
# nothing of the build in it:
#
#   docker run --rm --cap-add NET_RAW --cap-add SYS_NICE \
#       -v "$PWD:/src" -w /src debian:13 sh .github/try.sh
#
# (NET_RAW: the raw ICMP socket. SYS_NICE: pingerd raises its own
# priority when it starts.)
#
# The package installs with apt, which fetches what it depends on; the
# module pings 127.0.0.1; pingerd, started as the unit starts it, reads
# its hosts from the plan's database and answers on its web port with
# what it measured, as "nobody"; and the package can be removed again.
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

# 2. pingerd
python3 - <<'EOF'
import sqlite3
db = sqlite3.connect('/etc/ipplan.db')
db.execute('CREATE TABLE host (name TEXT, ipv4_addr_txt TEXT)')
db.execute("INSERT INTO host VALUES ('loopback.test', '127.0.0.1')")
db.execute("INSERT INTO host VALUES ('no-address.test', NULL)")
db.commit()
EOF
grep -xF 'ExecStart=/usr/sbin/pingerd' /usr/lib/systemd/system/pingerd.service
/usr/sbin/pingerd --port 13110 --interval 0.5 &
daemon=$!
stop() { kill "$daemon" 2>/dev/null || true; }
python3 - <<'EOF' || { stop; exit 1; }
import re
import sys
import time
import urllib.request

wanted = re.compile(
    r'^icmp_rtt_seconds_count\{host="loopback\.test"\} (\S+)$', re.M)
text = ''
for _ in range(40):
    time.sleep(0.5)
    try:
        text = urllib.request.urlopen(
            'http://127.0.0.1:13110/metrics', timeout=5).read().decode()
    except OSError:
        continue
    found = wanted.search(text)
    if found and float(found.group(1)) >= 3:
        print('pingerd: %s answers from 127.0.0.1 counted' % found.group(1))
        break
else:
    sys.exit('pingerd: no answers counted in 20 s; it said:\n' + text[-2000:])
if 'no-address.test' in text:
    sys.exit('pingerd: a host without an address was measured')
EOF
# it gave up root once the socket was open
uid=$(awk '/^Uid:/ {print $2}' "/proc/$daemon/status")
echo "pingerd runs as uid $uid (nobody is $(id -u nobody))"
test "$uid" = "$(id -u nobody)" || { stop; exit 1; }
stop

# 3. and it goes away again
apt-get remove -y -q pinger
test ! -e /usr/sbin/pingerd
test ! -e /usr/lib/systemd/system/pingerd.service
echo "ok: the package installs, runs and is removed"
