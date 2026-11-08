pkg_list_components() {
    local type=$1 package=$2 path inventory category
    if [[ $type == dependency ]]; then pkg_list_dependencies "$package"; return; fi
    inventory=$(mktemp)
    find "$package" -mindepth 1 \( -type f -o -type l \) -print0 | LC_ALL=C sort -z > "$inventory" || { rm -f -- "$inventory"; return 1; }
    while IFS= read -r -d '' path; do
        path=${path#"$package/"}
        category=$(pkg_category "$path")
        [[ $category != "$type" ]] || printf '%s\n' "$path"
    done < "$inventory"
    rm -f -- "$inventory"
}
