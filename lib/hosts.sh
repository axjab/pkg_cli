# Shared discovery and validation for publication destinations.
source "$(dirname -- "${BASH_SOURCE[0]}")/workspace.sh"
source "$(dirname -- "${BASH_SOURCE[0]}")/choose.sh"

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

pkg_select_host() {
    local explicit_syntax=$1 host candidate hosts_directory
    local -a hosts=()
    pkg_load_hosts || return

    case ${#hosts[@]} in
        0)
            printf 'pkg: no hosts configured. Use pkg host add <host>.\n' >&2
            return 1
            ;;
        1)
            pkg_debug host.selection only
            printf '%s\n' "${hosts[0]}"
            ;;
        *)
            pkg_debug host.selection ambiguous
            if [[ ! -t 0 ]]; then
                printf 'pkg: multiple hosts configured. Use %s.\n' "$explicit_syntax" >&2
                return 1
            fi
            host=$(pkg_choose 'Available hosts:' 'Host' "${hosts[@]}") || return
            for candidate in "${hosts[@]}"; do
                if [[ $candidate == "$host" ]]; then
                    pkg_debug host.selection interactive
                    printf '%s\n' "$host"
                    return 0
                fi
            done
            printf 'pkg: select a configured host\n' >&2
            return 1
            ;;
    esac
}
