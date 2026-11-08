#!/bin/sh
# Configure APT repositories on Debian 13 amd64, then refresh the package index.
set -eu
export LC_ALL=C

die() { printf 'install: %s\n' "$*" >&2; exit 1; }

# name, repository URL, suite, components, key URL, key format, optional SHA-256
add_repository() (
    [ "$#" -ge 6 ] && [ "$#" -le 7 ] || die 'invalid repository definition'
    name=$1 uri=$2 suite=$3 components=$4 key_url=$5 format=$6 digest=${7:-}
    case "$name" in ''|*[!a-z0-9-]*) die "invalid repository name: $name" ;; esac
    case "$format" in asc|gpg) ;; *) die "invalid key format: $format" ;; esac
    case "$uri:$key_url" in *'
'*) die 'repository URLs must be single lines' ;; esac
    case "$uri" in https://*) ;; *) die "HTTPS required: $uri" ;; esac
    case "$key_url" in https://*) ;; *) die "HTTPS required: $key_url" ;; esac
    [ ! -e "$work/files/$name.sources" ] || die "duplicate repository: $name"
    key=$name-archive.$format
    printf 'Preparing %s repository\n' "$name"
    curl -q --fail --silent --show-error --location --proto '=https' --proto-redir '=https' \
        --connect-timeout 10 --max-time 30 --max-filesize 1048576 \
        --retry 2 --retry-max-time 60 --output "$work/files/$key" "$key_url"
    [ -s "$work/files/$key" ] || die "empty signing key: $name"
    if [ "$format" = asc ]; then
        grep -q '^-----BEGIN PGP PUBLIC KEY BLOCK-----' "$work/files/$key" ||
            die "invalid armored signing key: $name (the server may have returned an error page)"
    fi
    if [ -n "$digest" ]; then
        actual=$(sha256sum < "$work/files/$key")
        [ "${actual%% *}" = "$digest" ] || die "signing key SHA-256 mismatch: $name"
    fi
    printf 'Types: deb\nURIs: %s\nSuites: %s\nComponents: %s\nArchitectures: amd64\nSigned-By: /etc/apt/keyrings/%s\n' \
        "$uri" "$suite" "$components" "$key" > "$work/files/$name.sources"
)

# Repository definitions live in repos/*.sh.
prepare_repositories() {
    (
#!/bin/sh
# Loaded by the bootstrap with add_repository available.
add_repository charm https://repo.charm.sh/apt/ '*' '*' \
    https://repo.charm.sh/apt/gpg.key asc

    )
    (
#!/bin/sh
# Loaded by the bootstrap with add_repository available.
add_repository docker https://download.docker.com/linux/debian trixie stable \
    https://download.docker.com/linux/debian/gpg asc

    )
    (
#!/bin/sh
# Loaded by the bootstrap with add_repository available.
add_repository eza https://deb.gierens.de stable main \
    https://raw.githubusercontent.com/eza-community/eza/main/deb.asc asc

    )
    (
#!/bin/sh
# Loaded by the bootstrap with add_repository available.
add_repository gopass https://packages.gopass.pw/repos/gopass stable main \
    https://packages.gopass.pw/repos/gopass/gopass-archive-keyring.gpg gpg

    )
    (
#!/bin/sh
# Loaded by the bootstrap with add_repository available.
add_repository mullvad https://repository.mullvad.net/deb/stable stable main \
    https://repository.mullvad.net/deb/mullvad-keyring.asc asc

    )
    (
#!/bin/sh
# Loaded by the bootstrap with add_repository available.
add_repository pkg https://apt.alj.cx trixie main \
    https://apt.alj.cx/apt-signing-key.asc asc \
    846503567f081b8cc241992a5c1115c59972e709109cb9843c2d82406152ba6a

    )
    (
#!/bin/sh
# Loaded by the bootstrap with add_repository available.
add_repository yazi https://yazi-rs.github.io/builds/ stable main \
    https://yazi-rs.github.io/builds/yazi-keyring.gpg gpg

    )
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
created= pending=
keep_repository=no
cleanup() {
    status=$?
    trap - EXIT
    if [ "$keep_repository" = no ]; then
        for file in $created; do
            rm -f -- "$file" || printf 'install: could not roll back %s\n' "$file" >&2
        done
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
    created="$2 $created"
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
# Check every destination before installing any file.
for staged in "$work"/files/*; do
    name=${staged##*/}
    case "$name" in
        *.sources) destination=/etc/apt/sources.list.d/$name ;;
        *) destination=/etc/apt/keyrings/$name ;;
    esac
    check_file "$staged" "$destination"
done
# Refuse legacy entries to avoid registering a repository twice.
for legacy in gopass yazi mullvad charm gierens docker pkg; do
    [ ! -e "/etc/apt/sources.list.d/$legacy.list" ] ||
        die "legacy source exists: /etc/apt/sources.list.d/$legacy.list; migrate it before retrying"
done
if [ ! -d /etc/apt/keyrings ]; then
    mkdir -m 0755 -- /etc/apt/keyrings || die 'cannot create /etc/apt/keyrings'
fi
for staged in "$work"/files/*; do
    name=${staged##*/}
    case "$name" in
        *.sources) destination=/etc/apt/sources.list.d/$name ;;
        *) destination=/etc/apt/keyrings/$name ;;
    esac
    if [ ! -e "$destination" ]; then
        install_config "$staged" "$destination"
    fi
done

apt-get --error-on=any update </dev/null || die 'APT update failed; newly added repository files will be removed'

keep_repository=yes
ROOT
}

main() {
    [ "$#" -eq 0 ] || die 'this script takes no arguments; select packages with apt install after setup'
    export LC_ALL=C
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

    mkdir "$work/files"
    prepare_repositories

    configure_repository "$work"
    printf 'APT repositories ready. To install a package, run: sudo apt install <package>\n'
}

main "$@"
