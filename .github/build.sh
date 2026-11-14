#!/bin/sh
# Builds the Debian package. Runs INSIDE a debian:13 container, in the
# source tree, as the workflows start it:
#
#   docker run --rm -v "$PWD:/src" -w /src debian:13 sh .github/build.sh
#
# It compiles the module with Debian 13's own compiler for Debian 13's
# own Python and leaves in dist/:
#
#   pinger_<version>_amd64.deb
#       /usr/sbin/pingerd                               the daemon
#       /usr/lib/python3/dist-packages/dhmonpinger.*.so its module
#       /usr/lib/systemd/system/pingerd.service         the unit
#       /usr/share/doc/pinger/copyright
#   SHA256SUMS
#
# The package depends on exactly the Python it was built for and on
# Debian's python3-prometheus-client; a server that installs it needs
# no compiler and nothing else from the internet. Whether it works is
# tried apart from here, on a machine that has only the package:
# .github/try.sh.
set -eu

version=$(sed -n "s/.*version='\([^']*\)'.*/\1/p" src/pinger/setup.py)
test -n "$version"

export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get install -y -q --no-install-recommends \
    gcc libc6-dev python3-dev python3-setuptools

# the module, built away from the tree
rm -rf dist /tmp/build
mkdir -p /tmp/build/lib /tmp/build/tmp
(cd src/pinger && python3 setup.py -q build_ext \
    --build-lib /tmp/build/lib --build-temp /tmp/build/tmp)
module=$(ls /tmp/build/lib/dhmonpinger.*.so)
strip --strip-unneeded "$module"
echo "built: $module"

# what the package says it needs: this Python (the module is tied to
# it) and the C library version the module's symbols ask for
arch=$(dpkg --print-architecture)
python=$(python3 -c 'import sys; print("%d.%d" % sys.version_info[:2])')
python_next=$(python3 -c \
    'import sys; print("%d.%d" % (sys.version_info[0], sys.version_info[1] + 1))')
glibc=$(objdump -T "$module" | sed -n 's/.*(GLIBC_\([0-9.]*\)).*/\1/p' \
    | sort -V | tail -1)
test -n "$glibc"

# the package's tree
root=/tmp/build/deb
install -D -m 755 src/pinger/pingerd "$root/usr/sbin/pingerd"
install -D -m 644 "$module" \
    "$root/usr/lib/python3/dist-packages/$(basename "$module")"
install -D -m 644 LICENSE "$root/usr/share/doc/pinger/copyright"
# the repository's unit, with the package's path
mkdir -p "$root/usr/lib/systemd/system"
sed 's|^ExecStart=/opt/pinger/pingerd$|ExecStart=/usr/sbin/pingerd|' \
    pingerd.service > "$root/usr/lib/systemd/system/pingerd.service"
grep -qxF 'ExecStart=/usr/sbin/pingerd' \
    "$root/usr/lib/systemd/system/pingerd.service"
chmod 644 "$root/usr/lib/systemd/system/pingerd.service"

size=$(du -sk "$root" | cut -f1)
mkdir "$root/DEBIAN"
sed -e "s/@VERSION@/$version/" -e "s/@ARCH@/$arch/" -e "s/@SIZE@/$size/" \
    -e "s/@PYTHON@/$python/" -e "s/@PYTHON_NEXT@/$python_next/" \
    -e "s/@GLIBC@/$glibc/" packaging/control.in > "$root/DEBIAN/control"
if grep -q '@[A-Z_]*@' "$root/DEBIAN/control"; then
    echo "packaging/control.in: something was not filled in"
    exit 1
fi
install -m 755 packaging/postinst packaging/prerm packaging/postrm \
    "$root/DEBIAN/"

mkdir dist
deb="dist/pinger_${version}_${arch}.deb"
dpkg-deb --root-owner-group --build "$root" "$deb"
dpkg-deb --info "$deb"
dpkg-deb --contents "$deb"

(cd dist && sha256sum ./*.deb > SHA256SUMS && cat SHA256SUMS && ls -l)
