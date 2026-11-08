#!/usr/bin/env bash
set -euo pipefail
pkg=${PKG_TEST_BINARY:?set PKG_TEST_BINARY}
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
cd "$work"
$pkg init >/dev/null
$pkg new demo >/dev/null
printf '#!/bin/sh\nexit 0\n' > gum
chmod 755 gum
$pkg add dependency gum to demo >/dev/null
$pkg add executable ./gum to demo >/dev/null
# script provides an actual terminal; NO_COLOR selects the plain prompt.
printf 'dependency in demo: gum\n' | NO_COLOR=1 script -qec "'$pkg' rm gum from demo" /dev/null > prompt
[[ -f .pkg/packages/demo/bin/gum && -z $($pkg ls dependency in demo) ]]
grep -F 'Matching targets:' prompt >/dev/null
printf 'dependency\n' | NO_COLOR=1 script -qec "'$pkg' add gum to demo" /dev/null > prompt
[[ $($pkg ls dependency in demo) == gum ]]
grep -F 'Component category:' prompt >/dev/null
# A package and an executable with the same name are also ambiguous.
$pkg new gum >/dev/null
printf '2\n' | NO_COLOR=1 script -qec "'$pkg' rm gum" /dev/null > prompt
[[ ! -d .pkg/packages/gum && -f .pkg/packages/demo/bin/gum ]]
# Invalid/cancelled choices must never mutate.
if printf 'not a choice\n' | NO_COLOR=1 script -qec "'$pkg' rm gum from demo" /dev/null > prompt; then exit 1; fi
[[ $($pkg ls dependency in demo) == gum && -f .pkg/packages/demo/bin/gum ]]
printf 'PASS: terminal disambiguation and invalid selection\n'
