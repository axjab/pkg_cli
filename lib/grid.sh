# Fixed-width, column-major layout, keeping each relationship entry intact.
pkg_dependency_grid() {
    local value=$1 indent=${2:-2} shade=$3 entry width=${COLUMNS:-80} longest=0 columns rows row column index line padded
    local -a entries=()
    value=${value//$'\n'/ }
    IFS=, read -r -a entries <<< "$value"
    for index in "${!entries[@]}"; do
        entry=${entries[index]}
        entry="${entry#"${entry%%[![:space:]]*}"}"
        entry="${entry%"${entry##*[![:space:]]}"}"
        entries[index]=$entry
        (( ${#entry} <= longest )) || longest=${#entry}
    done
    (( ${#entries[@]} )) || return 0
    if [[ -t 1 && -z ${COLUMNS:-} ]]; then width=$(tput cols 2>/dev/null) || width=80; fi
    [[ $width =~ ^[0-9]{1,4}$ ]] || width=80
    width=$((10#$width))
    columns=$(((width - indent) / (longest + 2)))
    (( columns >= 1 )) || columns=1
    (( columns <= ${#entries[@]} )) || columns=${#entries[@]}
    rows=$(( (${#entries[@]} + columns - 1) / columns ))
    for (( row=0; row<rows; row++ )); do
        printf -v line '%*s' "$indent" ''
        for (( column=0; column<columns; column++ )); do
            index=$((column * rows + row))
            (( index < ${#entries[@]} )) || break
            if (( index + rows < ${#entries[@]} )); then
                printf -v padded '%-*s' "$((longest + 2))" "${entries[index]}"
                line+=$padded
            else line+=${entries[index]}; fi
        done
        print_line "$shade" "$line"
    done
}
