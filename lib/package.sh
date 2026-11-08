# Package selection shared by commands that operate on one package.
source "$(dirname -- "${BASH_SOURCE[0]}")/workspace.sh"
source "$(dirname -- "${BASH_SOURCE[0]}")/choose.sh"

pkg_fail() {
    printf 'pkg: %s\n' "$1" >&2
    exit "${2:-1}"
}

pkg_require_workspace() {
    local root status
    if root=$(pkg_find_workspace); then
        printf '%s\n' "$root"
    else
        status=$?
        if (( status == 2 )); then
            pkg_fail 'not a pkg workspace (no .pkg in this directory or its parents)'
        fi
        return 1
    fi
}

pkg_package_ready() {
    [[ -d $1 && ! -L $1 && -d $1/DEBIAN && ! -L $1/DEBIAN && -f $1/DEBIAN/control && ! -L $1/DEBIAN/control ]]
}

pkg_select_package() {
    local packages="${1%/}/.pkg/packages" explicit_syntax=$2
    shift 2
    local name package directory candidate
    local -a candidates=()

    pkg_debug packages.directory "$packages"
    if [[ ! -d $packages || -L $packages ]]; then
        pkg_debug packages.storage invalid_or_missing
        pkg_fail "invalid package storage: $packages"
    fi
    pkg_debug packages.storage ready

    if (( $# == 1 )); then
        pkg_debug package.selection explicit
        name=$1
    else
        for directory in "$packages"/*; do
            candidate=${directory##*/}
            if [[ $candidate =~ ^[a-z0-9][a-z0-9+.-]+$ ]] && pkg_package_ready "$directory"; then
                candidates+=("$candidate")
            fi
        done
        pkg_debug packages.count "${#candidates[@]}"

        case ${#candidates[@]} in
            0)
                pkg_debug package.selection missing
                pkg_fail 'no packages available. Create one with pkg new <name>.'
                ;;
            1)
                pkg_debug package.selection only
                name=${candidates[0]}
                ;;
            *)
                if [[ ! -t 0 ]]; then
                    pkg_debug package.selection ambiguous
                    pkg_fail "multiple packages available. Use $explicit_syntax."
                fi
                pkg_debug package.selection interactive
                if name=$(pkg_choose 'Available packages:' 'Package name' "${candidates[@]}"); then
                    [[ -n $name ]] || pkg_fail 'no package selected'
                else
                    pkg_fail 'no package selected' "$?"
                fi
                ;;
        esac
    fi

    pkg_debug package.name "$name"
    if [[ ! $name =~ ^[a-z0-9][a-z0-9+.-]+$ ]]; then
        pkg_fail "invalid package name: $name" 2
    fi

    package="$packages/$name"
    pkg_debug package.target "$package"
    if [[ ! -e $package && ! -L $package ]]; then
        pkg_fail "unknown package '$name'. Create it with pkg new $name."
    fi
    if ! pkg_package_ready "$package"; then
        pkg_fail "invalid package layout: $package"
    fi

    printf '%s\n' "$package"
}
