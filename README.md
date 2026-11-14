# pinger

`pingerd` pings every host of the IP plan and says how long the answers
took, for Prometheus.

- **Whom it pings:** every host in `/etc/ipplan.db` (table `host`) that
  has an IPv4 address. The database is read again for every round, so
  new hosts are picked up without a restart; a host that has left the
  plan is pinged until the next restart.
- **How often:** once a second (`--interval`).
- **What it says:** the histogram `icmp_rtt_seconds`, one per host
  (label `host`), on `http://<server>:13110/metrics` (`--port`). A host
  that does not answer simply gets no new observations: compare
  `icmp_rtt_seconds_count` over time.
- **Rights:** it starts as root, opens one raw ICMP socket, raises its
  priority and then continues as `nobody`.

The sending and receiving is a small C module, `dhmonpinger`
(`src/pinger/dhmonpinger.c`); the daemon is `src/pinger/pingerd`.

## Running it

A release is a Debian package, built for Debian 13 - nothing is
compiled on the server:

    pinger_X.Y.Z_amd64.deb
        /usr/sbin/pingerd
        /usr/lib/python3/dist-packages/dhmonpinger.cpython-313-x86_64-linux-gnu.so
        /usr/lib/systemd/system/pingerd.service

    apt install ./pinger_X.Y.Z_amd64.deb
    systemctl enable --now pingerd

apt fetches what it depends on: Debian's `python3-prometheus-client`.
The package depends on exactly the Python it was built for (Debian
13's, 3.13) - the module is tied to it. Installing it starts nothing
(`pingerd` needs `/etc/ipplan.db`); an upgrade restarts a `pingerd`
that is running.

## Releasing

1. Set the version in `src/pinger/setup.py`.
2. Push; the `ci` workflow builds the package and tries it.
3. Tag that commit `vX.Y.Z` (the same version) and push the tag: the
   `release` workflow builds, tries and publishes the package and
   `SHA256SUMS` as a GitHub release.

Building is `.github/build.sh`. Trying is `.github/try.sh`, in a new
Debian 13 container that has no compiler: the package installs with
apt, the module pings 127.0.0.1 (`tests/loopback.py`), `pingerd` reads
its hosts from a plan database and answers on its web port with what it
measured, as `nobody`, and the package is removed again.

## Building by hand

    docker run --rm -v "$PWD:/src" -w /src debian:13 sh .github/build.sh
    docker run --rm --cap-add NET_RAW --cap-add SYS_NICE \
        -v "$PWD:/src:ro" -w /src debian:13 sh .github/try.sh

The first leaves the package in `dist/`. (With rootless podman the
second stops where `pingerd` raises its priority: that needs real
root.) The old `src/pinger/Makefile` (build and install straight onto
the machine it runs on, under `/opt/pinger`) is unchanged, and so is
`pingerd.service` in the repository, which names that path; the
package's unit names `/usr/sbin/pingerd`.
