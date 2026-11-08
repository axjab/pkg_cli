# Check output always goes to stderr; stdout is reserved for command results.
pkg_push_result() {
    local color=$1 message=$2
    if [[ -t 2 && -z ${NO_COLOR:-} ]]; then
        printf '\033[%sm%s\033[0m\n' "$color" "$message" >&2
    else
        printf '%s\n' "$message" >&2
    fi
}
