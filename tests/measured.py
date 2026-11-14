#!/usr/bin/python3
"""What a running pingerd says it measured.

  python3 tests/measured.py PORT --counted HOST... [--never HOST...]

Waits (20 s at most) until every --counted host has at least three
answers in icmp_rtt_seconds on http://127.0.0.1:PORT/metrics, and then
demands that no --never host appears there at all.
"""
import argparse
import re
import sys
import time
import urllib.request

parser = argparse.ArgumentParser()
parser.add_argument('port', type=int)
parser.add_argument('--counted', nargs='+', required=True)
parser.add_argument('--never', nargs='*', default=[])
args = parser.parse_args()


def count(text, host):
    found = re.search(
        r'^icmp_rtt_seconds_count\{host="%s"\} (\S+)$' % re.escape(host),
        text, re.M)
    return float(found.group(1)) if found else 0


text = ''
for _ in range(40):
    time.sleep(0.5)
    try:
        text = urllib.request.urlopen(
            'http://127.0.0.1:%d/metrics' % args.port, timeout=5
        ).read().decode()
    except OSError:
        continue
    if all(count(text, host) >= 3 for host in args.counted):
        break
else:
    sys.exit('pingerd on %d: not every one of %s was counted in 20 s; '
             'it said:\n%s' % (args.port, args.counted, text[-2000:]))
for host in args.never:
    if 'host="%s"' % host in text:
        sys.exit('pingerd on %d measured %s' % (args.port, host))
print('pingerd on %d: counted %s; never %s' % (
    args.port, ', '.join(args.counted), ', '.join(args.never) or '-'))
