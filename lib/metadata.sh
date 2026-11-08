pkg_metadata() {
    local action=$1 field value='' scope='' package lock
    shift
    if [[ ${1:-} == help ]]; then
        printf 'Usage: pkg get <field> [from <package>]\n       pkg set <field> <value> [in <package>]\nFields are case-insensitive; name aliases Package. Custom fields are supported.\n'
        return
    fi
    (( $# )) || pkg_fail 'metadata field is required' 2
    field=$1; shift
    if [[ $action == set ]]; then
        (( $# )) || pkg_fail 'metadata value is required' 2
        value=$1; shift
    fi
    case $# in
        0) ;;
        2) [[ $1 == in || $1 == from ]] || pkg_fail 'expected in/from <package>' 2; scope=$2 ;;
        *) pkg_fail 'invalid metadata arguments' 2 ;;
    esac
    root=$(pkg_require_workspace)
    [[ -d $root/.pkg/packages && ! -L $root/.pkg/packages ]] || pkg_fail 'invalid package storage'
    exec {lock}<"$root/.pkg/packages"
    if [[ $action == set ]]; then flock -x "$lock"; else flock -s "$lock"; fi
    local -a selection=()
    [[ -z $scope ]] || selection=("$scope")
    package=$(pkg_select_package "$root" "pkg $action <field> ... in <package>" "${selection[@]}")
    if [[ $action == get ]]; then pkg_get_field "$package" "$field"
    elif [[ $(pkg_field "$field") == Package ]]; then pkg_rename_package "$package" "$value"
    else pkg_set_field "$package" "$field" "$value"; fi
}
