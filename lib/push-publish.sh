# Activate a prepared release while the repository write lock is held.
activate_release() {
    local filename=$1 force=$2 stage_suite="$probe_dir/dists/trixie"
    live_suite="$repository/dists/trixie"
    live_archive="$repository/pool/main/$filename"
    publish_archive="$probe_dir/pool/main/$filename"
    live_public_key="$repository/apt-signing-key.asc"
    publish_public_key="$probe_dir/apt-signing-key.asc"
    commit_marker="$probe_dir/activated-inrelease"

    # Keep a reference to the new signature so cleanup can tell if the swap happened.
    ln -T -- "$stage_suite/InRelease" "$commit_marker" ||
        fail 'could not prepare the release activation marker'
    mkdir -p -- "$repository/pool/main" "$repository/dists" ||
        fail 'could not create the public repository directories'

    if [[ -e $live_archive || -L $live_archive ]]; then
        [[ -f $live_archive && ! -L $live_archive ]] || fail "invalid archive at $live_archive"
        if ! cmp -s -- "$publish_archive" "$live_archive"; then
            [[ $force == 1 ]] || fail "different archive already exists at $live_archive"
            # Keep the old archive in staging until the signed suite is live.
            replacement_marker="$probe_dir/replacement-archive"
            ln -T -- "$publish_archive" "$replacement_marker" ||
                fail 'could not prepare archive replacement'
            mv --exchange --no-copy -T -- "$publish_archive" "$live_archive" ||
                fail "could not replace $live_archive"
        fi
    else
        ln -T -- "$publish_archive" "$live_archive" || fail "could not publish $live_archive"
    fi
    if [[ -f $publish_public_key ]]; then
        ln -T -- "$publish_public_key" "$live_public_key" ||
            fail "could not publish the public signing key at $live_public_key"
    fi

    if [[ -d $live_suite ]]; then
        mv --exchange --no-copy -T -- "$stage_suite" "$live_suite" ||
            fail 'could not exchange the staged and live suite directories'
    else
        mv --no-copy -T -- "$stage_suite" "$live_suite" ||
            fail 'could not activate the staged suite directory'
    fi
    pkg_debug push.live_release "$live_suite/InRelease"
}

cleanup_push() {
    local status=$?
    trap - EXIT
    # On a failed activation, restore a replaced archive or remove a new one.
    if [[ -n ${commit_marker:-} && ! $commit_marker -ef $live_suite/InRelease ]]; then
        if [[ -n ${replacement_marker:-} && $replacement_marker -ef $live_archive ]]; then
            if ! mv --exchange --no-copy -T -- "$publish_archive" "$live_archive"; then
                pkg_push_result 31 "pkg: could not roll back $live_archive. Original archive retained at $publish_archive"
                exit 1
            fi
        elif [[ $publish_archive -ef $live_archive ]]; then
            rm -f -- "$live_archive" || pkg_push_result 31 "pkg: could not roll back $live_archive"
        fi
        if [[ $publish_public_key -ef $live_public_key ]]; then
            rm -f -- "$live_public_key" || pkg_push_result 31 "pkg: could not roll back $live_public_key"
        fi
    fi
    rm -rf -- "$probe_dir" || pkg_push_result 31 "pkg: could not remove staging at $probe_dir"
    exit "$status"
}
