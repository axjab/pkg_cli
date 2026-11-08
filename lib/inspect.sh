source "$(dirname -- "${BASH_SOURCE[0]}")/categories.sh"
# Inspect the staged tree using Bash and standard filesystem utilities.
pkg_inspect() (
    local package=$1 line field='' value key path category display target
    local -a order=() paths=() groups=()
    local -A populated=()
    local -A fields=()
    local -a names=('DEBIAN/control' 'Dependencies' 'Executables' 'Configuration' 'Services' 'Documentation' 'Shared assets' 'Desktop assets' 'Package metadata' 'Lifecycle scripts' 'Other')
    local -a colors=(91 96 92 93 96 97 95 94 91 93 97)
    local -a secondary=(31 36 32 33 36 37 35 34 31 33 37)
    local color=false
    [[ -t 1 && -z ${NO_COLOR:-} && ${TERM:-dumb} != dumb ]] && color=true

    [[ -d $package/DEBIAN && ! -L $package/DEBIAN && -f $package/DEBIAN/control && ! -L $package/DEBIAN/control ]] ||
        pkg_fail 'invalid DEBIAN/control'
    while IFS= read -r line || [[ -n $line ]]; do
        if [[ $line == [$' \t']* ]]; then
            [[ -n $field ]] || pkg_fail 'control continuation without a field'
            fields[$field]+=$'\n'"${line:1}"
        elif [[ -z $line ]]; then
            field=''
        elif [[ $line == *:* ]]; then
            key=${line%%:*}
            field=${key,,}
            [[ $field =~ ^[a-z0-9][a-z0-9-]*$ ]] || pkg_fail 'invalid control field'
            [[ ! -v fields[$field] ]] || pkg_fail "duplicate control field: $key"
            value=${line#*:}
            value=${value# }
            fields[$field]=$value
            order+=("$field")
        else
            pkg_fail 'invalid control line'
        fi
    done < "$package/DEBIAN/control"

    # Capture traversal errors before rendering; never follow payload symlinks.
    local inventory
    inventory=$(mktemp)
    trap 'rm -f -- "$inventory"' EXIT
    find "$package" -mindepth 1 -print0 | LC_ALL=C sort -z > "$inventory"
    while IFS= read -r -d '' path; do
        path=${path#"$package/"}
        case $(pkg_category "$path") in
            control) category=0 ;;
            executable) category=2 ;;
            configuration) category=3 ;;
            service) category=4 ;;
            documentation) category=5 ;;
            asset) category=6 ;;
            desktop) category=7 ;;
            metadata) category=8 ;;
            lifecycle) category=9 ;;
            *) category=10 ;;
        esac
        if [[ ! -d $package/$path || -L $package/$path ]]; then
            populated[$category]=1
        fi
        # Nonempty directories are implied by their contents. Empty ones are entries.
        if [[ -d $package/$path && ! -L $package/$path ]]; then
            local -a children=()
            shopt -s nullglob dotglob
            children=("$package/$path"/*)
            (( ${#children[@]} == 0 )) || continue
            path+=/
        fi
        printf -v display '%q' "$path"
        if [[ -L $package/$path ]]; then
            target=$(readlink -- "$package/$path")
            printf -v target '%q' "$target"
            display+=" -> $target"
        fi
        paths+=("$display")
        groups+=("$category")
    done < "$inventory"

    print_line() {
        local shade=$1 text=$2
        if [[ $color == true ]]; then
            printf '\033[%sm%s\033[0m\n' "$shade" "$text"
        else
            printf '%s\n' "$text"
        fi
    }
    for category in "${!names[@]}"; do
        case $category in
            5|7|10) [[ ${populated[$category]:-0} == 1 ]] || continue ;;
        esac
        (( category == 0 )) || printf '\n'
        print_line "1;${colors[$category]}" "${names[$category]}"
        local count=0
        if (( category == 0 )); then
            for key in "${order[@]}"; do
                case $key in
                    depends|pre-depends|recommends|suggests|enhances|breaks|conflicts|provides|replaces) continue ;;
                esac
                print_line "${secondary[$category]}" "  ${key^}: ${fields[$key]}"
                count=$((count + 1))
            done
        elif (( category == 1 )); then
            for key in depends pre-depends recommends suggests enhances breaks conflicts provides replaces; do
                if [[ -v fields[$key] ]]; then
                    print_line "${secondary[$category]}" "  ${key^}: ${fields[$key]}"
                    count=$((count + 1))
                fi
            done
        else
            local index
            for index in "${!paths[@]}"; do
                if [[ ${groups[$index]} == "$category" ]]; then
                    print_line "${secondary[$category]}" "  ${paths[$index]}"
                    count=$((count + 1))
                fi
            done
        fi
        (( count )) || print_line "${secondary[$category]}" '  (empty)'
    done
)
