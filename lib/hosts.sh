# Shared discovery and validation for publication destinations.
source "$(dirname -- "${BASH_SOURCE[0]}")/workspace.sh"

pkg_valid_host() {
    [[ $1 =~ ^([a-zA-Z0-9_][a-zA-Z0-9_.-]*@)?[a-zA-Z0-9_:][a-zA-Z0-9_.:%-]*$ ]]
}

pkg_load_hosts() {
    local root status entry host LC_COLLATE=C
    if root=$(pkg_find_workspace); then
        :
    else
        status=$?
        if (( status == 2 )); then
            printf 'pkg: not a pkg workspace (no .pkg in this directory or its parents)\n' >&2
        fi
        return 1
    fi

    hosts_directory="${root%/}/.pkg/hosts"
    hosts=()
    pkg_debug hosts.directory "$hosts_directory"
    if [[ -L $hosts_directory || ( -e $hosts_directory && ! -d $hosts_directory ) ]]; then
        printf 'pkg: invalid host storage: %s\n' "$hosts_directory" >&2
        return 1
    fi
    for entry in "$hosts_directory"/*; do
        [[ -e $entry || -L $entry ]] || continue
        host=${entry##*/}
        if [[ ! -d $entry || -L $entry ]] || ! pkg_valid_host "$host"; then
            printf 'pkg: invalid host entry: %s\n' "$entry" >&2
            return 1
        fi
        pkg_debug "hosts.name[${#hosts[@]}]" "$host"
        hosts+=("$host")
    done
    pkg_debug hosts.count "${#hosts[@]}"
}
