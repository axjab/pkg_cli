#!/bin/bash
set -euo pipefail
base=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
pkg=${PKG_TEST_BINARY:?Set PKG_TEST_BINARY to the compiled pkg executable}
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
cd "$work"
"$pkg" init >/dev/null
"$pkg" new demo >/dev/null
p=.pkg/packages/demo
for directory in DEBIAN bin usr/bin usr/sbin etc/demo usr/lib/systemd/system etc/init.d usr/share/doc/demo usr/share/man/man1 usr/share/demo usr/lib/demo usr/share/applications usr/share/icons; do
    test -d "$p/$directory"
done
mkdir -p "$p"/{usr/bin,etc/systemd/system,usr/share/doc/demo,usr/share/applications,usr/lib/demo,opt/demo}
touch "$p/usr/bin/demo" "$p/etc/systemd/system/demo.service" "$p/usr/share/doc/demo/copyright" "$p/usr/share/applications/demo.desktop" "$p/usr/lib/demo/asset" "$p/DEBIAN/postinst"
ln -s /nonexistent "$p/opt/demo/link"
"$pkg" ls demo > view
for heading in 'DEBIAN/control' Dependencies Executables Configuration Services Documentation 'Shared assets' 'Desktop assets' 'Package metadata' 'Lifecycle scripts' Other; do
    grep -Fx "$heading" view >/dev/null
done
grep -F '  etc/systemd/system/demo.service' view
grep -F '  opt/demo/link -> /nonexistent' view
! grep -q $'\033' view
rmdir "$p/bin"
"$pkg" ls demo >/dev/null
env -u NO_COLOR TERM=xterm script -q -c "'$pkg' ls demo" /dev/null > color
grep -q $'\033\[1;92mExecutables' color
grep -q $'\033\[32m  usr/bin/demo' color
NO_COLOR=1 TERM=xterm script -q -c "'$pkg' ls demo" /dev/null > plain
! grep -q $'\033' plain
echo 'Inspector checks passed'
