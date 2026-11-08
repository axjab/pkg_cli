# Values arrive through the environment, never through awk code or -v escapes.
function fail(msg) { print "pkg: " msg > "/dev/stderr"; failed=1; exit 1 }
BEGIN { wanted=tolower(ENVIRON["PKG_FIELD"]); replacement=ENVIRON["PKG_VALUE"] }
/^[ \t]/ {
    if (!key) fail("control continuation without field")
    values[key]=values[key] "\n" substr($0,2)
    next
}
/^$/ { if (count) separator=1; next }
{
    if (separator) fail("expected one control stanza")
    colon=index($0,":")
    if (!colon) fail("invalid control line")
    name=substr($0,1,colon-1); key=tolower(name)
    if (key !~ /^[a-z0-9][a-z0-9-]*$/ || key in names) fail("invalid or duplicate control field")
    names[key]=name; order[++count]=key
    value=substr($0,colon+1); sub(/^ /,"",value); values[key]=value
}
END {
    if (failed) exit 1
    if (action=="get") {
        if (!(wanted in names)) fail("metadata field not found: " wanted)
        print values[wanted]; exit
    }
    if (!(wanted in names)) { order[++count]=wanted; names[wanted]=ENVIRON["PKG_FIELD"] }
    values[wanted]=replacement
    for(i=1;i<=count;i++) {
        key=order[i]; value=values[key]; gsub(/\n/,"\n ",value)
        print names[key] ": " value
    }
}
