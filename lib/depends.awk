# Read or update the Depends field of a single binary package control stanza.
function trim(value) {
    sub(/^[ \t]+/, "", value)
    sub(/[ \t]+$/, "", value)
    return value
}

function normalized(value) {
    gsub(/[ \t]+/, " ", value)
    gsub(/ *\| */, " | ", value)
    gsub(/ *\( */, " (", value)
    gsub(/ *\)/, ")", value)
    return trim(value)
}

function fail(message) {
    print "pkg: " message > "/dev/stderr"
    failed = 1
    exit 1
}

{
    lines[NR] = $0
    if ($0 ~ /^[ \t]*$/) {
        if (seen_field && !separator)
            separator = NR
        next
    }
    if (separator)
        fail("expected one stanza in DEBIAN/control")
    if (tolower($0) ~ /^depends:/) {
        if (first)
            fail("multiple Depends fields in DEBIAN/control")
        first = last = NR
        value = substr($0, index($0, ":") + 1)
    } else if (last && NR == last + 1 && $0 ~ /^[ \t]/) {
        value = value " " trim($0)
        last = NR
    }
    seen_field = 1
}

END {
    if (failed)
        exit 1

    entry = trim(ENVIRON["PKG_DEP_ENTRY"])
    count = split(trim(value), items, ",")
    for (i = 1; i <= count; i++) {
        item = items[i] = trim(items[i])
        if (item == "")
            fail("empty entry in Depends")
        if (action == "list")
            continue
        if (normalized(item) == normalized(entry)) {
            found = 1
            if (action == "remove")
                continue
        }
        updated = updated (updated == "" ? "" : ", ") item
    }
    if (action == "list") {
        for (i = 1; i <= count; i++)
            print items[i]
        exit
    }

    if (action == "remove" && !found)
        fail("dependency is not staged: " entry)
    if (action == "add" && !found)
        updated = updated (updated == "" ? "" : ", ") entry

    if (action == "add" && found) {
        for (i = 1; i <= NR; i++)
            print lines[i]
        exit
    }

    if (!first)
        first = separator ? separator : NR + 1
    for (i = 1; i <= NR + 1; i++) {
        if (i == first && updated != "")
            print "Depends: " updated
        if (i <= NR && !(i >= first && i <= last))
            print lines[i]
    }
}
