# Shared workspace discovery; sourced by pkg subcommands.
pkg_find_workspace() {
    local directory
    directory=$(pwd -P) || return
    while :; do
        if [[ -e "$directory/.pkg" || -L "$directory/.pkg" ]]; then
            if [[ ! -d "$directory/.pkg" || -L "$directory/.pkg" ]]; then
                printf 'pkg: invalid workspace directory: %s/.pkg\n' "$directory" >&2
                return 1
            fi
            printf '%s\n' "$directory"
            return 0
        fi
        [[ "$directory" != / ]] || return 2
        directory=${directory%/*}
        directory=${directory:-/}
    done
}
