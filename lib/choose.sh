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

# Package menus deliberately use typed numbers, including when Gum is installed.
# Persist names rather than indexes: sorting changes must not change the default.
pkg_choose_package() {
    local packages=$1 choice saved='' default='' index state temporary
    shift
    local -a names=("$@")
    state="${packages%/packages}/.last-package-$UID"
    if [[ -f $state && ! -L $state ]]; then IFS= read -r saved < "$state" || :; fi
    printf 'Available packages:\n' >&2
    for index in "${!names[@]}"; do
        printf '  %d) %s\n' "$((index + 1))" "${names[index]}" >&2
        [[ ${names[index]} != "$saved" ]] || default=$((index + 1))
    done
    while :; do
        if [[ -n $default ]]; then printf 'Package number [%s]: ' "$default" >&2
        else printf 'Package number: ' >&2; fi
        IFS= read -r choice || return 1
        if [[ -z $choice && -z $default ]]; then return 1; fi
        choice=${choice:-$default}
        if [[ $choice =~ ^[0-9]{1,6}$ ]] && (( 10#$choice >= 1 && 10#$choice <= ${#names[@]} )); then
            index=$((10#$choice - 1))
            temporary=$(mktemp -- "${packages%/packages}/.selection.XXXXXXXX") || return
            printf '%s\n' "${names[index]}" > "$temporary"
            if ! mv -fT -- "$temporary" "$state"; then rm -f -- "$temporary"; return 1; fi
            printf '%s\n' "${names[index]}"
            return
        fi
        printf 'Enter a listed package number.\n' >&2
    done
}
