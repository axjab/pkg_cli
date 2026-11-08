# Shared Depends queries and updates for staged binary package metadata.
pkg_dependency_control() {
    local metadata="$1/DEBIAN"
    if [[ ! -d $metadata || -L $metadata || ! -f $metadata/control || -L $metadata/control ]]; then
        pkg_fail "invalid package control file: $metadata/control"
    fi
    printf '%s\n' "$metadata/control"
}

pkg_list_dependencies() {
    local control
    control=$(pkg_dependency_control "$1")
    awk -v action=list -f "$(dirname -- "${BASH_SOURCE[0]}")/depends.awk" "$control"
}

pkg_change_dependency() (
    local action=$1 root=$2 package=$3 entry=$4 control lock staging candidate
    if [[ $entry != *[!$' \t']* || $entry == *[$',\r\n']* ]]; then
        pkg_fail 'expected one Depends entry' 2
    fi

    # Lock the package directory so concurrent edits read the latest control
    # file even when the previous editor atomically replaced that file.
    exec {lock}<"$package"
    flock -x "$lock"
    control=$(pkg_dependency_control "$package")
    staging=$(mktemp -d -- "${root%/}/.pkg/.depends.XXXXXXXX")
    trap 'rm -rf -- "$staging"' EXIT
    mkdir -p -- "$staging/package/DEBIAN"
    candidate="$staging/package/DEBIAN/control"
    PKG_DEP_ENTRY="$entry" awk -v action="$action" \
        -f "$(dirname -- "${BASH_SOURCE[0]}")/depends.awk" "$control" > "$candidate"

    if cmp -s -- "$control" "$candidate"; then
        printf 'Dependency already staged: %s\n' "$entry"
        return 0
    fi
    # Use Debian's relationship parser without building the workspace payload.
    dpkg-deb --root-owner-group --build "$staging/package" "$staging/check.deb" >/dev/null
    chmod --reference="$control" -- "$candidate"
    mv --no-copy -fT -- "$candidate" "$control"
    printf 'Updated Depends (%s): %s\n' "$action" "$entry"
)
