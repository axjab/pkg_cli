# Shared workspace discovery; sourced by pkg subcommands.
pkg_debug() {
    [[ ${PKG_DEBUG:-0} == 1 ]] || return 0
    local key=$1 value=$2 value_color=$'\033[0m'
    if [[ -n ${NO_COLOR:-} ]]; then
        printf 'pkg.debug.%s=%q\n' "$key" "$value" >&2
        return
    fi
    case $value in
        true) value_color=$'\033[32m' ;;
        false) value_color=$'\033[31m' ;;
    esac
    printf '\033[36mpkg.debug.%s\033[0m=%s%q\033[0m\n' "$key" "$value_color" "$value" >&2
}

pkg_find_workspace() {
    local directory start marker present
    directory=$(pwd -P) || return
    start=$directory
    pkg_debug workspace.start "$start"
    while :; do
        marker="${directory%/}/.pkg"
        present=false
        if [[ -e $marker || -L $marker ]]; then
            present=true
        fi
        if [[ $directory == "$start" ]]; then
            pkg_debug workspace.current_marker_present "$present"
        fi
        pkg_debug workspace.checked "$marker"
        pkg_debug workspace.marker_present "$present"
        if [[ $present == true ]]; then
            if [[ ! -d $marker || -L $marker ]]; then
                pkg_debug workspace.discovered false
                pkg_debug workspace.result invalid_marker
                printf 'pkg: invalid workspace directory: %s\n' "$marker" >&2
                return 1
            fi
            pkg_debug workspace.discovered true
            if [[ $directory == "$start" ]]; then
                pkg_debug workspace.result current
            else
                pkg_debug workspace.result ancestor
            fi
            pkg_debug workspace.root "$directory"
            pkg_debug workspace.marker "$marker"
            printf '%s\n' "$directory"
            return 0
        fi
        if [[ $directory == / ]]; then
            pkg_debug workspace.discovered false
            pkg_debug workspace.result missing
            return 2
        fi
        directory=${directory%/*}
        directory=${directory:-/}
    done
}
