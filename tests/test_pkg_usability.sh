#!/usr/bin/env bash
set -euo pipefail
pkg=${PKG_TEST_BINARY:?set PKG_TEST_BINARY}
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
cd "$work"
reject() { if "$@" >out 2>err; then printf 'unexpected success: %s\n' "$*" >&2; exit 1; fi; }
$pkg init >/dev/null
$pkg new alpha >/dev/null
$pkg new beta >/dev/null
$pkg add dependency gum 2.0.2 to alpha >/dev/null
[[ $($pkg get Depends from alpha) == 'gum (>= 2.0.2)' ]]
$pkg add dependency curl '= 8.0' to alpha >/dev/null
$pkg add wget '<< 3.0' to alpha >/dev/null
$pkg add dependency libc6 '>=2.0' to alpha >/dev/null
$pkg add dependency bash 5.0 to alpha >/dev/null
cp .pkg/packages/alpha/DEBIAN/control before
for version in '' nope '(>= 2.0)' '>= 2.0, bad' '> 1' '2.0 3.0'; do
    reject "$pkg" add dependency invalid "$version" to alpha
    cmp before .pkg/packages/alpha/DEBIAN/control
done
reject "$pkg" add dependency gum to ''
# Grid is multi-column at a wide width, keeps version constraints intact,
# and switches to single-column output at narrow widths.
COLUMNS=120 $pkg ls alpha > wide
awk '/^Dependencies$/{active=1;next} active && /^$/{exit} active{print}' wide > grid
[[ $(wc -l < grid) == 1 ]]
grep -F 'gum (>= 2.0.2)' grid >/dev/null
grep -F 'curl (= 8.0)' grid >/dev/null
! grep -q 'Depends:' grid
COLUMNS=20 $pkg ls alpha > narrow
awk '/^Dependencies$/{active=1;next} active && /^$/{exit} active{print}' narrow > grid
[[ $(wc -l < grid) == 5 ]]
$pkg set Recommends 'nano, vim' in alpha
COLUMNS=80 $pkg ls alpha > wide
grep -F '  Recommends:' wide >/dev/null
# Fake editor confirms the exact control file and makes an observable edit.
cat > "$work/my editor" <<'EDITOR'
#!/usr/bin/env bash
printf '%s\n' "$1" > "$EDITOR_LOG"
printf 'X-Edited: yes\n' >> "$1"
EDITOR
chmod 755 "$work/my editor"
export EDITOR_LOG="$work/editor.log" VISUAL="$work/my editor"
$pkg edit alpha
[[ $(cat "$EDITOR_LOG") == "$work/.pkg/packages/alpha/DEBIAN/control" ]]
[[ $($pkg get X-Edited from alpha) == yes ]]
# Package selection ignores Gum and accepts numbers only; Enter recalls beta.
printf 'beta\n99\n2\n' | script -qec "'$pkg' get name" /dev/null > prompt
grep -F 'Enter a listed package number.' prompt >/dev/null
grep -F '2) beta' prompt >/dev/null
[[ $(cat .pkg/.last-package-"$UID") == beta ]]
printf '\n' | script -qec "'$pkg' edit" /dev/null > prompt
[[ $(cat "$EDITOR_LOG") == "$work/.pkg/packages/beta/DEBIAN/control" ]]
grep -F 'Package number [2]:' prompt >/dev/null
# A remembered default never silently targets a package in scripts.
reject "$pkg" get name
# A stale remembered choice offers no default, and blank cancels cleanly.
$pkg rm package beta >/dev/null
$pkg new gamma >/dev/null
if printf '\n' | script -qec "'$pkg' get name" /dev/null > prompt; then exit 1; fi
! grep -F 'Package number [2]:' prompt
[[ $(cat .pkg/.last-package-"$UID") == beta ]]
# Copy errors retain the underlying status, clean staging, and emit debug events.
printf '#!/bin/sh\nexit 0\n' > demo
chmod 755 demo
mkdir tools
cat > tools/install <<'INSTALL'
#!/usr/bin/env bash
printf partial > "${@: -1}"
exit 7
INSTALL
chmod 755 tools/install
set +e
PATH="$work/tools:$PATH" $pkg --debug add executable ./demo to alpha >out 2>err
status=$?
set -e
[[ $status == 7 ]]
grep -F 'pkg.debug.add.result=failed' err >/dev/null
[[ ! -e .pkg/packages/alpha/bin/demo ]]
shopt -s nullglob
leftovers=(.pkg/.add.*)
(( ${#leftovers[@]} == 0 ))
$pkg --debug add executable ./demo to alpha >out 2>err
grep -F 'pkg.debug.add.result=staged' err >/dev/null
$pkg --debug add executable ./demo to alpha >out 2>err
grep -F 'pkg.debug.add.result=already_staged' err >/dev/null
printf 'PASS: dependency grid/version, editor, numbered defaults, and copy failures\n'
