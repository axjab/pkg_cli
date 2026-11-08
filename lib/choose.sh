# Prompt on a terminal and return the selected value on stdout.
pkg_choose() {
    local heading=$1 prompt=$2 choice candidate
    shift 2

    if [[ -t 2 && -z ${NO_COLOR:-} && ${TERM:-dumb} != dumb ]]; then
        if ! command -v gum >/dev/null; then
            printf 'pkg: interactive selection requires gum. Install it with apt or set NO_COLOR=1 for a plain prompt.\n' >&2
            return 1
        fi
        choice=$(gum choose --header "$heading" --limit 1 -- "$@") || return
        for candidate in "$@"; do
            if [[ $candidate == "$choice" ]]; then
                printf '%s\n' "$choice"
                return 0
            fi
        done
        return 1
    fi

    printf '%s\n' "$heading" >&2
    printf '  %s\n' "$@" >&2
    printf '%s: ' "$prompt" >&2
    IFS= read -r choice || return
    printf '%s\n' "$choice"
}
