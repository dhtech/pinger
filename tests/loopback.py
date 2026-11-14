#!/usr/bin/python3
"""The built module pings 127.0.0.1 and gets its own answer back.

  python3 tests/loopback.py [DIRECTORY WITH THE BUILT MODULE]

Without a directory: the installed module. Needs the right to open a
raw socket (root, or CAP_NET_RAW). Run when a package is tried
(.github/try.sh); by hand, without root, in a network namespace of
your own:

  unshare -r -n sh -c 'ip link set lo up && python3 tests/loopback.py DIR'
"""
import os
import signal
import sys
import time

if len(sys.argv) > 1:
    sys.path.insert(0, sys.argv[1])

import dhmonpinger  # noqa: E402

ROUNDS = 5

# receive() waits for ever when nothing comes back
signal.alarm(20)

sock = dhmonpinger.create_socket()

# the receive buffer: with CAP_NET_ADMIN it is what the module asks
# for, whatever net.core.rmem_max says (PINGER_FULL_BUFFER=1 demands
# that); without, the kernel may have cut it down
wanted = 2 * dhmonpinger.RCVBUF
got = dhmonpinger.receive_buffer(sock)
try:
    with open('/proc/sys/net/core/rmem_max') as handle:
        limit = handle.read().strip()
except OSError:
    limit = 'unknown'
print('receive buffer: %d bytes (asked for %d; net.core.rmem_max is %s)'
      % (got, wanted, limit))
assert 0 < got <= wanted, got
if os.environ.get('PINGER_FULL_BUFFER') == '1':
    assert got == wanted, 'the buffer was not forced'
for n in range(ROUNDS):
    # what pingerd sends along: the time of the round, in seconds -
    # and once a number that needs all 64 bits of the field
    stamp = int(time.time()) if n else 2**64 - 2
    dhmonpinger.transmit(sock, '127.0.0.1', stamp)
    ip, user, secs, usecs = dhmonpinger.receive(sock)
    assert ip == '127.0.0.1', ip
    assert user == stamp, (user, stamp)
    rtt = secs + usecs / 1e6
    assert 0 <= rtt < 1, rtt
    print('127.0.0.1: answer %d of %d in %.6f s' % (n + 1, ROUNDS, rtt))

# an address that is none is refused, not sent to
try:
    dhmonpinger.transmit(sock, 'not-an-address', 0)
except IOError:
    pass
else:
    raise SystemExit('transmit() took "not-an-address"')
print('ok')
