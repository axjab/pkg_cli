source "$(dirname -- "${BASH_SOURCE[0]}")/package.sh"
source "$(dirname -- "${BASH_SOURCE[0]}")/depends.sh"
source "$(dirname -- "${BASH_SOURCE[0]}")/categories.sh"

pkg_field() {
    case ${1,,} in name|package) printf Package ;; *) printf '%s' "$1" ;; esac
}
pkg_get_field() {
    local control
    control=$(pkg_dependency_control "$1")
    PKG_FIELD=$(pkg_field "$2") awk -v action=get -f "$lib/control.awk" "$control"
}
pkg_set_field() (
    local package=$1 field value=$3 staging control lock
    field=$(pkg_field "$2")
    [[ $field =~ ^[a-zA-Z0-9][a-zA-Z0-9-]*$ && $value != *$'\r'* && -n $value ]] || pkg_fail 'invalid metadata field or empty value' 2
    exec {lock}<"$package"
    flock -x "$lock"
    control=$(pkg_dependency_control "$package") || return
    staging=$(mktemp -d -- "$root/.pkg/.control.XXXXXXXX") || return
    trap 'rm -rf -- "$staging"; rm -f -- "$staging.deb"' EXIT
    mkdir -p -- "$staging/DEBIAN" || return
    PKG_FIELD=$field PKG_VALUE=$value awk -v action=set -f "$lib/control.awk" "$control" > "$staging/DEBIAN/control" || return
    dpkg-deb --root-owner-group --build "$staging" "$staging.deb" >/dev/null || return
    rm -f -- "$staging.deb"
    chmod --reference="$control" -- "$staging/DEBIAN/control" || return
    mv -fT -- "$staging/DEBIAN/control" "$control"
)
# Reject traversal and symlink ancestors. A leaf symlink can be renamed/removed.
pkg_safe_path() {
    local package=$1 relative=$2 part current=$1
    [[ -n $relative && $relative != /* && $relative != */ && $relative != *$'\n'* ]] || pkg_fail 'expected a package-relative path' 2
    local -a parts
    IFS=/ read -r -a parts <<< "$relative"
    for part in "${parts[@]}"; do
        [[ -n $part && $part != . && $part != .. ]] || pkg_fail 'path traversal is not allowed' 2
        current+="/$part"
        [[ $current == "$package/$relative" ]] && break
        [[ ! -L $current ]] || pkg_fail "symlink ancestor: $relative"
        [[ ! -e $current || -d $current ]] || pkg_fail "non-directory ancestor: $relative"
    done
}
pkg_rename_package() {
    local package=$1 name=$2 old=${1##*/} destination staged
    [[ $name =~ ^[a-z0-9][a-z0-9+.-]+$ && $name != help ]] || pkg_fail 'invalid package name' 2
    [[ $old != "$name" ]] || return 0
    destination="$root/.pkg/packages/$name"
    [[ ! -e $destination && ! -L $destination ]] || pkg_fail "package already exists: $name"
    # Work on a copy; invalid control values never damage the original package.
    staged=$(mktemp -d -- "$root/.pkg/.rename.XXXXXXXX")
    cp -a -- "$package/." "$staged/" || { rm -rf -- "$staged"; return 1; }
    if ! pkg_set_field "$staged" Package "$name"; then rm -rf -- "$staged"; return 1; fi
    mv -T -n -- "$staged" "$destination"
    if [[ -d $staged ]]; then rm -rf -- "$staged"; pkg_fail 'rename destination appeared concurrently'; fi
    rm -rf -- "$package"
    printf 'Renamed package: %s -> %s\n' "$old" "$name"
}
pkg_add_candidate() {
    candidate_types+=("$1")
    candidate_packages+=("$2")
    candidate_values+=("$3")
    labels+=("$1 in ${2##*/}: $3")
}
pkg_resolve() {
    local type=$1 query=$2 scope=$3 directory path category entry selected i inventory dependencies
    candidate_types=(); candidate_packages=(); candidate_values=(); labels=()
    for directory in "$root/.pkg/packages"/*; do
        [[ ${directory##*/} =~ ^[a-z0-9][a-z0-9+.-]+$ ]] || continue
        pkg_package_ready "$directory" || continue
        [[ -z $scope || ${directory##*/} == "$scope" ]] || continue
        if [[ -z $scope && ( -z $type || $type == package ) && ${directory##*/} == "$query" ]]; then
            pkg_add_candidate package "$directory" "$query"
        fi
        if [[ -z $type || $type == dependency ]]; then
            dependencies=$(pkg_list_dependencies "$directory") || return
            while IFS= read -r entry; do
                [[ -n $entry ]] || continue
                if [[ $entry == "$query" || $entry == "$query ("* || $entry == "$query:"* ]]; then
                    pkg_add_candidate dependency "$directory" "$entry"
                fi
            done <<< "$dependencies"
        fi
        [[ $type != package && $type != dependency ]] || continue
        inventory=$(mktemp)
        find "$directory" -mindepth 1 \( -type f -o -type l \) -print0 | LC_ALL=C sort -z > "$inventory" || { rm -f -- "$inventory"; return 1; }
        while IFS= read -r -d '' path; do
            path=${path#"$directory/"}
            [[ $path == "$query" || ${path##*/} == "$query" ]] || continue
            category=$(pkg_category "$path")
            [[ -z $type || $category == "$type" ]] || continue
            pkg_add_candidate "$category" "$directory" "$path"
        done < "$inventory"
        rm -f -- "$inventory"
    done
    # When matches span packages, select the package first using the shared menu.
    local -a matching_packages=() kept_types=() kept_packages=() kept_values=() kept_labels=()
    local -A matched=()
    for directory in "${candidate_packages[@]}"; do
        if [[ ! -v matched[$directory] ]]; then
            matched[$directory]=1; matching_packages+=("${directory##*/}")
        fi
    done
    if (( ${#matching_packages[@]} > 1 )) && [[ -t 0 ]]; then
        selected=$(pkg_choose_package "$root/.pkg/packages" "${matching_packages[@]}") || pkg_fail 'no package selected'
        for i in "${!labels[@]}"; do
            [[ ${candidate_packages[i]##*/} == "$selected" ]] || continue
            kept_types+=("${candidate_types[i]}"); kept_packages+=("${candidate_packages[i]}")
            kept_values+=("${candidate_values[i]}"); kept_labels+=("${labels[i]}")
        done
        candidate_types=("${kept_types[@]}"); candidate_packages=("${kept_packages[@]}")
        candidate_values=("${kept_values[@]}"); labels=("${kept_labels[@]}")
    fi
    case ${#labels[@]} in
        0) pkg_fail "no matching ${type:-component or package}: $query" ;;
        1) selected=${labels[0]} ;;
        *)
            [[ -t 0 ]] || pkg_fail "ambiguous '$query'; use an explicit category and package (for example: pkg rm dependency '$query' from <package>), or a package-relative path" 2
            selected=$(pkg_choose 'Matching targets:' 'Target (copy a listed choice)' "${labels[@]}") || pkg_fail 'no target selected'
            ;;
    esac
    for i in "${!labels[@]}"; do
        if [[ ${labels[i]} == "$selected" ]]; then
            resolved_type=${candidate_types[i]}; package=${candidate_packages[i]}; item=${candidate_values[i]}
            return
        fi
    done
    pkg_fail 'select a listed target' 2
}
pkg_default_path() {
    local type=$1 name=$2 package_name=$3
    case $type in
        executable) printf 'bin/%s' "$name" ;;
        configuration) printf 'etc/%s/%s' "$package_name" "$name" ;;
        service) printf 'usr/lib/systemd/system/%s' "$name" ;;
        documentation) printf 'usr/share/doc/%s/%s' "$package_name" "$name" ;;
        asset) printf 'usr/share/%s/%s' "$package_name" "$name" ;;
        desktop) case $name in *.desktop) printf 'usr/share/applications/%s' "$name" ;; *) printf 'usr/share/icons/%s' "$name" ;; esac ;;
        lifecycle|metadata) printf 'DEBIAN/%s' "$name" ;;
        other) pkg_fail 'other requires an explicit destination: as <package-relative-path>' 2 ;;
        *) pkg_fail "cannot add category: $type" 2 ;;
    esac
}
pkg_infer_add() {
    local source=$1 path=${1#./} inferred selected candidate
    local -a choices=()
    if [[ -e $source || -L $source ]]; then
        inferred=$(pkg_category "${path#/}")
        if [[ $inferred != other ]]; then choices+=("$inferred")
        else
            case $source in
                *.service|*.socket|*.timer|*.target|*.path|*.mount|*.automount|*.slice) choices+=(service) ;;
                *.conf|*.cfg) choices+=(configuration) ;;
                *.desktop) choices+=(desktop) ;;
            esac
            [[ ! -x $source || ! -f $source ]] || choices+=(executable)
        fi
        if (( ${#choices[@]} == 0 )); then
            choices=(executable configuration service documentation asset desktop metadata lifecycle other)
        fi
        # A bare word may denote an APT dependency as well as a local file.
        [[ ! $source =~ ^[a-z0-9][a-z0-9+.-]+$ ]] || choices+=(dependency)
    else
        choices=(dependency)
    fi
    if [[ $source != */* ]] && pkg_package_ready "$root/.pkg/packages/$source"; then choices+=(package); fi
    if (( ${#choices[@]} == 1 )); then printf '%s' "${choices[0]}"; return; fi
    [[ -t 0 ]] || pkg_fail 'ambiguous source; specify a category (for example: pkg add executable ./file to <package>)' 2
    selected=$(pkg_choose 'Component category:' 'Category' "${choices[@]}") || pkg_fail 'no category selected'
    for candidate in "${choices[@]}"; do [[ $candidate != "$selected" ]] || { printf '%s' "$selected"; return; }; done
    pkg_fail 'select a listed category' 2
}
pkg_action() {
    local action=$1 type='' scope='' destination='' source='' new='' staging mode actual version='' status force=0 target
    shift
    if [[ ${1:-} == help ]]; then
        cat <<HELP
Usage: pkg add [-f] [<category>] <source> [as <path>] [to <package>]
       pkg add dependency <name> [<version-or-constraint>] [to <package>]
       pkg mv [<category>] <old> to <new> [in <package>]
       pkg rm [<category>] <item> [from <package>]
Categories: package, dependency, executable, configuration, service,
            documentation, asset, desktop, metadata, lifecycle, other.
Use new to create a package; set/get manage DEBIAN/control fields.
Paths are package-relative. Ambiguous terminal input prompts; scripts must
supply category/package/path. rm package removes the local staged definition.
Use add -f to replace an existing regular file at the staging destination.
HELP
        return
    fi
    if [[ $action == add && ${1:-} == -f ]]; then
        force=1
        shift
    fi
    if type=$(pkg_type "${1:-}"); then shift; else type=''; fi
    [[ ${1:-} != -- ]] || shift
    local -a args=("$@")
    local count=${#args[@]}
    if (( count >= 3 )); then
        case ${args[count-2]} in
            in|from) scope=${args[count-1]}; [[ -n $scope ]] || pkg_fail 'package name cannot be empty' 2; unset 'args[count-1]' 'args[count-2]' ;;
            to) if [[ $action != mv ]]; then scope=${args[count-1]}; [[ -n $scope ]] || pkg_fail 'package name cannot be empty' 2; unset 'args[count-1]' 'args[count-2]'; fi ;;
        esac
    fi
    set -- "${args[@]}"
    # Preserve the old add/rm <item> <package> shorthand.
    if [[ $action == add && $# == 2 && ( $type == dependency || ( -z $type && $2 =~ ^[0-9\<\>\=] ) ) ]]; then
        version=$2
        [[ -n $version ]] || pkg_fail 'dependency version cannot be empty' 2
        type=dependency
        set -- "$1"
    elif [[ $action != mv && $# == 2 ]]; then
        [[ -z $scope && -n $2 ]] || pkg_fail 'unexpected extra argument or empty package name' 2
        scope=$2; set -- "$1"
    fi
    case $action:$# in
        add:1|rm:1) source=$1 ;;
        add:3) [[ $2 == as ]] || pkg_fail 'expected as <destination>' 2; source=$1; destination=$3 ;;
        mv:3) [[ $2 == to ]] || pkg_fail 'expected mv <old> to <new> [in <package>]' 2; source=$1; new=$3 ;;
        *) pkg_fail "invalid syntax; use pkg help $action" 2 ;;
    esac
    root=$(pkg_require_workspace)
    [[ -d $root/.pkg/packages && ! -L $root/.pkg/packages ]] || pkg_fail 'invalid package storage'
    local workspace_lock
    exec {workspace_lock}<"$root/.pkg/packages"
    flock -x "$workspace_lock"
    if [[ -n $scope ]]; then pkg_select_package "$root" "pkg $action ... in <package>" "$scope" >/dev/null; fi
    if [[ $action == add ]]; then
        [[ -n $type ]] || type=$(pkg_infer_add "$source")
        [[ $type != package ]] || pkg_fail 'use pkg new <name> to create a package' 2
        local -a selection=()
        [[ -z $scope ]] || selection=("$scope")
        package=$(pkg_select_package "$root" 'pkg add <category> <item> to <package>' "${selection[@]}")
        if [[ $type == dependency ]]; then
            [[ $force == 0 ]] || pkg_fail 'add -f replaces files only. Use pkg mv to replace a dependency.' 2
            [[ -z $destination ]] || pkg_fail 'dependencies do not have file destinations' 2
            [[ -z $version ]] || source=$(pkg_dependency_with_version "$source" "$version")
            pkg_change_dependency add "$root" "$package" "$source"
            return
        fi
        [[ -f $source && -r $source ]] || pkg_fail "source is not a readable regular file: $source"
        [[ $type != executable || -x $source ]] || pkg_fail 'executable source must have execute permission'
        [[ -n $destination ]] || destination=$(pkg_default_path "$type" "${source##*/}" "${package##*/}")
        pkg_safe_path "$package" "$destination"
        actual=$(pkg_category "$destination")
        [[ $actual == "$type" ]] || pkg_fail "destination belongs to $actual, not $type" 2
        [[ $actual != control ]] || pkg_fail 'use pkg set to edit DEBIAN/control' 2
        mode=644; [[ $type != executable && $type != lifecycle ]] || mode=755
        staging=$(mktemp -- "$root/.pkg/.add.XXXXXXXX")
        if install -m "$mode" -- "$source" "$staging"; then :
        else status=$?; rm -f -- "$staging"; pkg_debug add.result failed; return "$status"; fi
        target="$package/$destination"
        if mkdir -p -- "${target%/*}" && mv -T -n -- "$staging" "$target"; then :
        else status=$?; rm -f -- "$staging"; pkg_debug add.result failed; return "$status"; fi
        if [[ -e $staging ]]; then
            if [[ -f $target && ! -L $target ]]; then
                if cmp -s -- "$staging" "$target"; then
                    rm -f -- "$staging"
                    pkg_debug add.result already_staged
                    return 0
                fi
                if [[ $force == 1 ]]; then
                    if mv --no-copy -fT -- "$staging" "$target"; then
                        pkg_debug add.result replaced
                        printf 'Replaced %s: %s\n' "$type" "$destination"
                        return 0
                    else
                        status=$?
                        rm -f -- "$staging"
                        pkg_debug add.result failed
                        return "$status"
                    fi
                fi
                rm -f -- "$staging"
                pkg_fail "destination already exists: $destination. Use -f to replace it."
            fi
            rm -f -- "$staging"
            pkg_fail "destination already exists: $destination and is not a regular file"
        fi
        pkg_debug add.result staged
        printf 'Added %s: %s\n' "$type" "$destination"
        return
    fi
    pkg_resolve "$type" "$source" "$scope"
    case $resolved_type in
        package)
            if [[ $action == mv ]]; then pkg_rename_package "$package" "$new"
            else rm -rf -- "$package"; printf 'Removed package: %s\n' "$item"; fi
            ;;
        dependency)
            if [[ $action == rm ]]; then pkg_change_dependency remove "$root" "$package" "$item"
            else pkg_replace_dependency "$package" "$item" "$new"; fi
            ;;
        control) pkg_fail 'DEBIAN/control is required; use pkg set to edit its fields' ;;
        *)
            pkg_safe_path "$package" "$item"
            if [[ $action == rm ]]; then rm -- "$package/$item"; printf 'Removed: %s\n' "$item"; return; fi
            if [[ $new != */* ]]; then new="${item%/*}/$new"; fi
            pkg_safe_path "$package" "$new"
            [[ $new != DEBIAN/control ]] || pkg_fail 'use pkg set to edit DEBIAN/control'
            [[ ! -e $package/$new && ! -L $package/$new ]] || pkg_fail "destination already exists: $new"
            mkdir -p -- "$package/$(dirname -- "$new")"
            mv -T -n -- "$package/$item" "$package/$new"
            [[ ! -e $package/$item && ! -L $package/$item ]] || pkg_fail 'rename destination appeared concurrently'
            printf 'Renamed: %s -> %s\n' "$item" "$new"
            ;;
    esac
}
pkg_replace_dependency() (
    local package=$1 old=$2 new=$3 entry joined='' found=false dependencies
    local -A seen=()
    [[ -n $new && $new != *[$',\r\n']* ]] || pkg_fail 'expected one replacement dependency entry' 2
    dependencies=$(pkg_list_dependencies "$package") || return
    while IFS= read -r entry; do
        [[ -n $entry ]] || continue
        if [[ $entry == "$old" ]]; then entry=$new; found=true; fi
        [[ ! -v seen[$entry] ]] || continue
        seen[$entry]=1
        [[ -z $joined ]] || joined+=', '
        joined+="$entry"
    done <<< "$dependencies"
    [[ $found == true ]] || pkg_fail 'dependency no longer exists'
    pkg_set_field "$package" Depends "$joined"
    printf 'Replaced dependency: %s -> %s\n' "$old" "$new"
)
