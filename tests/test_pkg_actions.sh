#!/usr/bin/env bash
set -euo pipefail
pkg=${PKG_TEST_BINARY:?set PKG_TEST_BINARY to compiled pkg}
root=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
expected_version=$(sed -n 's/^Version: //p' "$root/packaging/pkg-cli.control")
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
cd "$work"
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
reject() { if "$@" >out 2>err; then fail "unexpected success: $*"; fi; }
[[ -n $expected_version && $($pkg version) == "$expected_version" ]] || fail version
$pkg init >/dev/null
$pkg new alpha >/dev/null
$pkg set Version 1.2.3 in alpha
[[ $($pkg get version from alpha) == 1.2.3 ]] || fail version-field
$pkg set X-Owner 'my team: ops\literal' in alpha
[[ $($pkg get x-owner from alpha) == 'my team: ops\literal' ]] || fail custom-field
$pkg set Description $'Summary\nLong description\n.\nAnother paragraph' in alpha
[[ $($pkg get description from alpha) == $'Summary\nLong description\n.\nAnother paragraph' ]] || fail multiline
cp .pkg/packages/alpha/DEBIAN/control before
reject "$pkg" set Version 'invalid version' in alpha
cmp before .pkg/packages/alpha/DEBIAN/control || fail invalid-mutation
$pkg add dependency 'gum (>= 2.0.2)' to alpha >/dev/null
$pkg mv dependency gum to 'gum (>= 2.1)' in alpha >/dev/null
[[ $($pkg ls dependency in alpha) == 'gum (>= 2.1)' ]] || fail dep-replace
cp .pkg/packages/alpha/DEBIAN/control before
reject "$pkg" mv dependency gum to 'gum (garbage)' in alpha
cmp before .pkg/packages/alpha/DEBIAN/control || fail dep-rollback
printf '#!/bin/sh\nexit 0\n' > gum
chmod 755 gum
$pkg add ./gum to alpha >/dev/null
reject "$pkg" rm gum from alpha
[[ -f .pkg/packages/alpha/bin/gum ]] || fail ambiguous-deletion
$pkg mv executable gum to gum-cli in alpha >/dev/null
[[ $($pkg ls executable in alpha) == bin/gum-cli ]] || fail exe-query
printf 'content\n' > sample
reject "$pkg" add sample to alpha
reject "$pkg" add ./sample to alpha
for category in configuration service documentation asset desktop metadata lifecycle other; do
    case $category in
        service) target=usr/lib/systemd/system/demo.service ;;
        configuration) target=etc/alpha/sample.conf ;;
        documentation) target=usr/share/doc/alpha/README ;;
        asset) target=usr/share/alpha/sample ;;
        desktop) target=usr/share/applications/demo.desktop ;;
        metadata) target=DEBIAN/triggers ;;
        lifecycle) target=DEBIAN/postinst ;;
        other) target=opt/alpha/sample ;;
    esac
    $pkg add "$category" sample as "$target" to alpha >/dev/null
    [[ $($pkg ls "$category" in alpha) == "$target" ]] || fail "query $category"
    if [[ $category != lifecycle ]]; then
        $pkg mv "$category" "$target" to renamed in alpha >/dev/null
        target=${target%/*}/renamed
    fi
    $pkg rm "$target" from alpha >/dev/null
    [[ ! -e .pkg/packages/alpha/$target ]] || fail "remove $category"
done
reject "$pkg" add asset sample as ../escape to alpha
ln -s "$work" .pkg/packages/alpha/usr/share/escape
reject "$pkg" add asset sample as usr/share/escape/escaped to alpha
[[ ! -e escaped ]] || fail symlink-escape
$pkg rm usr/share/escape from alpha >/dev/null
reject "$pkg" rm DEBIAN/control from alpha
reject "$pkg" add metadata sample as DEBIAN/control to alpha
$pkg new beta >/dev/null
$pkg add executable ./gum to beta >/dev/null
$pkg add executable ./gum to alpha >/dev/null
reject "$pkg" rm executable gum
$pkg rm executable gum from beta >/dev/null
$pkg mv package beta to gamma >/dev/null
[[ $($pkg get name from gamma) == gamma && ! -d .pkg/packages/beta ]] || fail rename-package
$pkg set name delta in gamma >/dev/null
[[ $($pkg get Package from delta) == delta && ! -d .pkg/packages/gamma ]] || fail set-name
reject "$pkg" set name alpha in delta
[[ $($pkg get name from delta) == delta ]] || fail name-collision
$pkg rm package delta >/dev/null
[[ ! -d .pkg/packages/delta ]] || fail rm-package
$pkg rm dependency gum from alpha >/dev/null
[[ -z $($pkg ls dependency in alpha) ]] || fail rm-dep
$pkg new service >/dev/null
$pkg ls service > view
grep -Fx 'DEBIAN/control' view >/dev/null || fail category-name-collision
$pkg rm package service >/dev/null
# Concurrent edits must retain every field and dependency.
pids=()
for index in 1 2 3 4; do
    $pkg set "X-Test-$index" "$index" in alpha &
    pids+=("$!")
    $pkg add dependency "test-dependency-$index" to alpha >/dev/null &
    pids+=("$!")
done
for pid in "${pids[@]}"; do wait "$pid"; done
for index in 1 2 3 4; do
    [[ $($pkg get "X-Test-$index" from alpha) == "$index" ]] || fail concurrent-field
    $pkg rm dependency "test-dependency-$index" from alpha >/dev/null
done
$pkg build alpha >/dev/null
[[ -f dist/alpha_1.2.3_all.deb ]] || fail build
printf 'PASS: action schema, categories, metadata, ambiguity, safety, and build\n'
