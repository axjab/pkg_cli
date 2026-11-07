#!/usr/bin/env bash
set -euo pipefail
scripts=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/lib" && pwd)
trial=$(mktemp -d)
trap 'rm -rf -- "$trial"' EXIT
cd "$trial"
expect_failure() {
    local wanted=$1 actual=0
    shift
    "$@" >out 2>err || actual=$?
    [[ $actual == "$wanted" && -s err ]]
}
expect_failure 1 "$scripts/pkg-ls"
[[ ! -e .pkg ]]
"$scripts/pkg-init" >out
[[ -d .pkg/packages ]]
[[ -z $("$scripts/pkg-ls") ]]
mkdir -p .pkg/packages/{hello,core}/DEBIAN
printf 'preserve me\n' >.pkg/packages/core/DEBIAN/control
"$scripts/pkg-init" >out
[[ $(cat .pkg/packages/core/DEBIAN/control) == 'preserve me' ]]
[[ $("$scripts/pkg-ls") == $'core\nhello' ]]
mkdir 'child space'
cd 'child space'
[[ $("$scripts/pkg-ls") == $'core\nhello' ]]
"$scripts/pkg-init" >out
[[ ! -e .pkg ]]
mkdir -p .pkg/packages
[[ -z $("$scripts/pkg-ls") ]]
cd "$trial"
expect_failure 2 "$scripts/pkg-init" helloworld
expect_failure 2 "$scripts/pkg-ls" unexpected
mkdir "$trial/invalid"
cd "$trial/invalid"
touch .pkg
expect_failure 1 "$scripts/pkg-init"
expect_failure 1 "$scripts/pkg-ls"
[[ -f .pkg ]]
rm .pkg
ln -s "$trial/.pkg" .pkg
expect_failure 1 "$scripts/pkg-init"
expect_failure 1 "$scripts/pkg-ls"
rm .pkg
mkdir .pkg
touch .pkg/packages
expect_failure 1 "$scripts/pkg-init"
expect_failure 1 "$scripts/pkg-ls"
printf 'PASS: empty initialization, listing, preservation, ancestor discovery, nearest workspace, invalid arguments and storage.\n'
