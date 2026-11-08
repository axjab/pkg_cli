#!/bin/sh
# pkg_cli APT repository setup. Set these two values before hosting this file.
# Obtain the digest of the exact armored key from the trusted publisher host.
REPO_URL='https://apt.alj.cx'
KEY_SHA256='846503567f081b8cc241992a5c1115c59972e709109cb9843c2d82406152ba6a'

set -eu

die() {
    printf 'install: %s\n' "$*" >&2
    exit 1
}

configure_repository() {
    set -- /usr/bin/flock -w 30 /run/pkg-cli-install.lock /bin/sh -s -- "$@"
    if ( : </dev/tty ) 2>/dev/null; then
        set -- sudo -- "$@"
    else
        set -- sudo -n -- "$@"
    fi
    "$@" <<'ROOT'
set -eu
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
unset APT_CONFIG
umask 022

die() { printf 'install: %s\n' "$*" >&2; exit 1; }

work=$1
keyring=/etc/apt/keyrings/pkg-archive.asc
source=/etc/apt/sources.list.d/pkg.sources
new_key= new_source= pending=
keep_repository=no
cleanup() {
    status=$?
    trap - EXIT
    if [ "$keep_repository" = no ]; then
        if [ -n "$new_source" ]; then rm -f -- "$source" || printf 'install: could not roll back %s\n' "$source" >&2; fi
        if [ -n "$new_key" ]; then rm -f -- "$keyring" || printf 'install: could not roll back %s\n' "$keyring" >&2; fi
    fi
    if [ -n "$pending" ]; then rm -f -- "$pending" || :; fi
    exit "$status"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

check_path() {
    [ ! -L "$1" ] || die "refusing symlink: $1"
    owner_mode=$(stat -c '%u %a' -- "$1") || die "cannot inspect $1"
    [ "${owner_mode%% *}" = 0 ] || die "expected root ownership: $1"
    mode=${owner_mode#* }
    [ "$((0$mode & 022))" -eq 0 ] || die "group or other users can write to $1"
}

check_file() {
    if [ -e "$2" ] || [ -L "$2" ]; then
        [ -f "$2" ] || die "expected a regular file: $2"
        check_path "$2"
        cmp -s -- "$1" "$2" || die "conflicting configuration at $2"
    fi
}

install_config() {
    pending=$(mktemp -- "${2%/*}/.pkg-cli.XXXXXXXX") || die "cannot stage $2"
    install -m 0644 -- "$1" "$pending" || die "cannot prepare $2"
    ln -T -- "$pending" "$2" || die "cannot activate $2"
    if [ "$2" = "$keyring" ]; then new_key=yes; else new_source=yes; fi
    rm -f -- "$pending" || die "cannot remove staging for $2"
    pending=
}

for dir in /etc /etc/apt /etc/apt/sources.list.d; do
    [ -d "$dir" ] || die "missing directory: $dir"
    check_path "$dir"
done
if [ -e /etc/apt/keyrings ] || [ -L /etc/apt/keyrings ]; then
    [ -d /etc/apt/keyrings ] || die 'expected /etc/apt/keyrings to be a directory'
    check_path /etc/apt/keyrings
fi
check_file "$work/key.asc" "$keyring"
check_file "$work/installed.sources" "$source"

if [ ! -d /etc/apt/keyrings ]; then
    mkdir -m 0755 -- /etc/apt/keyrings || die 'cannot create /etc/apt/keyrings'
fi
if [ ! -e "$keyring" ]; then
    install_config "$work/key.asc" "$keyring"
fi
if [ ! -e "$source" ]; then
    install_config "$work/installed.sources" "$source"
fi

apt-get --error-on=any update </dev/null || die 'APT update failed; newly added repository files will be removed'

keep_repository=yes
ROOT
}

main() {
    [ "$#" -eq 0 ] || die 'this script takes no arguments; select packages with apt install after setup'
    export LC_ALL=C
    case "$REPO_URL" in
        https://*) ;;
        *) die 'the publisher must configure REPO_URL with its HTTPS repository URL' ;;
    esac
    case "${REPO_URL#https://}" in
        ''|/*|*[!a-zA-Z0-9./:-]*) die 'invalid repository URL; use an HTTPS host and optional path' ;;
    esac
    repo=${REPO_URL%/}
    case "$KEY_SHA256" in
        *[!a-f0-9]*) die 'KEY_SHA256 must be lowercase hexadecimal' ;;
    esac
    [ "${#KEY_SHA256}" -eq 64 ] || die 'the publisher must configure the pinned key SHA-256'

    [ "$(id -u)" -ne 0 ] || die 'run as a normal user; the installer uses sudo for system changes'
    [ -r /etc/os-release ] || die 'cannot identify this Linux distribution'
    . /etc/os-release
    [ "${ID:-}:${VERSION_ID:-}:${VERSION_CODENAME:-}" = debian:13:trixie ] ||
        die 'this repository supports Debian 13 (trixie)'
    for tool in curl sudo apt-get dpkg sha256sum mktemp; do
        command -v "$tool" >/dev/null || die "required command missing: $tool"
    done
    [ "$(dpkg --print-architecture)" = amd64 ] || die 'this repository supports amd64'

    work=$(mktemp -d /tmp/pkg-cli-bootstrap.XXXXXXXX) || die 'cannot create private staging'
    trap 'rm -rf -- "$work" || :' EXIT
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM

    curl -q --fail --silent --show-error --proto '=https' --connect-timeout 10 \
        --max-time 30 --max-filesize 65536 --retry 2 --retry-max-time 60 \
        --output "$work/key.asc" "$repo/apt-signing-key.asc" ||
        die 'could not download the repository signing key'
    digest=$(sha256sum < "$work/key.asc") || die 'could not hash the signing key'
    [ "${digest%% *}" = "$KEY_SHA256" ] || die 'repository signing key SHA-256 mismatch'

    printf 'Types: deb\nURIs: %s\nSuites: trixie\nComponents: main\nArchitectures: amd64\nSigned-By: /etc/apt/keyrings/pkg-archive.asc\n' \
        "$repo" > "$work/installed.sources" || die 'cannot write APT source'

    configure_repository "$work" || die 'repository setup failed; see the error above'
    printf 'APT repository ready. To install a package, run: sudo apt install <package>\n'
}

main "$@"
