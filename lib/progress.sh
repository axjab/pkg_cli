# Run a command with a terminal-only spinner while keeping its diagnostics
# separate from the animation. stdout remains untouched for command results.
pkg_run_with_spinner() {
    local message=$1 output status spinner_pid
    shift

    if [[ ! -t 2 ]]; then
        "$@"
        return $?
    fi

    output=$(mktemp "${TMPDIR:-/tmp}/pkg-progress.XXXXXXXX") || {
        "$@"
        return $?
    }

    (
        trap "printf '\r\033[K\033[?25h' >&2" EXIT
        sleep 0.15
        printf '\033[?25l' >&2
        local -a frames=('|' '/' '-' '\')
        local frame=0
        while :; do
            printf '\r\033[K%s %s' "${frames[frame]}" "$message" >&2
            frame=$(( (frame + 1) % ${#frames[@]} ))
            sleep 0.12
        done
    ) &
    spinner_pid=$!

    if "$@" 2>"$output"; then
        status=0
    else
        status=$?
    fi

    kill "$spinner_pid" 2>/dev/null || true
    wait "$spinner_pid" 2>/dev/null || true
    printf '\r\033[K\033[?25h' >&2
    cat -- "$output" >&2
    rm -f -- "$output"
    return "$status"
}
