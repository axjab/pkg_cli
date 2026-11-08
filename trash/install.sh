#!/bin/sh
set -eu

main() {
    if [ "$(id -u)" -ne 0 ]; then
        printf '%s\n' 'Run this script as root, for example with sudo sh.' >&2
        exit 1
    fi

    . /etc/os-release
    if [ "${ID:-}" != debian ] || [ "${VERSION_CODENAME:-}" != trixie ] ||
        [ "$(dpkg --print-architecture)" != amd64 ]; then
        printf '%s\n' 'This repository currently supports Debian 13 (trixie) on amd64.' >&2
        exit 1
    fi

    source_file=/etc/apt/sources.list.d/alj.sources
    staged_source=$(mktemp "${source_file%/*}/.alj.sources.XXXXXX")
    trap 'rm -f -- "$staged_source"' EXIT
    trap 'exit 1' HUP INT TERM
    cat > "$staged_source" <<'SOURCE'
Types: deb
URIs: https://fs.alj.cx/apt
Suites: trixie
Components: main
Architectures: amd64
Signed-By:
  -----BEGIN PGP PUBLIC KEY BLOCK-----
  .
  mDMEat4OCBYJKwYBBAHaRw8BAQdAzWdjtz/1dZBGTzZWjaxykjphzboaya59mwtn
  QndZjAK0EkFMSiBBUFQgUmVwb3NpdG9yeYiWBBMWCgA+FiEEw+Dquc9bnmwdnN0v
  83QO1a6z4P0FAmreDggCGwMFCQPCZwAFCwkIBwIGFQoJCAsCBBYCAwECHgECF4AA
  CgkQ83QO1a6z4P1mbgEA8qi3keMtgT+rlzJ0mgM7wRXE8yzTj3UsZeBs8QydSFgA
  /3A8byLrQr07h3fHLygBrP5ZjPMsHHQp7yxVBsnfcswI
  =Imz3
  -----END PGP PUBLIC KEY BLOCK-----
SOURCE

    # Preserve a different source file so APT settings are never silently replaced.
    if [ -e "$source_file" ] || [ -L "$source_file" ]; then
        if ! cmp -s "$staged_source" "$source_file"; then
            printf 'Review the existing %s before running this installer.\n' "$source_file" >&2
            exit 1
        fi
    else
        chmod 0644 "$staged_source"
        # Link into place atomically and fail if another process created the file.
        ln -T -- "$staged_source" "$source_file"
    fi
    rm -f -- "$staged_source"

    apt-get update --error-on=any
    apt-get install -y core
}

main "$@"

