# Build an APT repository view beneath the private push staging directory.
prepare_metadata() (
    local repository=$1 stage=$2 incoming=$3 force=${4:-0}
    local pool_path=pool/main release_path=dists/trixie
    local index_path=main/binary-amd64
    local package version architecture filename archive relative destination existing_identity incoming_identity
    local records=1 index_count entry digest_line digest bytes release release_date directory previous
    local -a indexes=("$index_path/Packages" "$index_path/Packages.gz")
    export LC_ALL=C

    package=$(dpkg-deb -f "$incoming" Package) || fail 'could not read the uploaded package name'
    version=$(dpkg-deb -f "$incoming" Version) || fail 'could not read the uploaded package version'
    architecture=$(dpkg-deb -f "$incoming" Architecture) || fail 'could not read the uploaded architecture'
    [[ $package =~ ^[a-z0-9][a-z0-9+.-]+$ &&
       $version =~ ^([0-9]+:)?[0-9][A-Za-z0-9.+~:-]*$ &&
       ( $architecture == amd64 || $architecture == all ) ]] ||
        fail 'invalid package identity for the trixie amd64 index'
    # dpkg-deb omits the epoch from the archive filename.
    filename="${package}_${version#*:}_${architecture}.deb"
    pkg_debug push.pool_target "$repository/$pool_path/$filename"
    mkdir -p -- "$stage/$pool_path" "$stage/$release_path" ||
        fail 'could not create the metadata staging directories'

    # Carry forward other suite files and old index hashes for readers of an earlier InRelease.
    if [[ -d $repository/$release_path ]]; then
        for previous in InRelease Release; do
            [[ -f $repository/$release_path/$previous ]] || continue
            awk '
                /^Architectures:/ { for (i=2; i<=NF; i++) if ($i != "amd64" && $i != "all") exit 1 }
                /^Components:/    { for (i=2; i<=NF; i++) if ($i != "main") exit 1 }
            ' "$repository/$release_path/$previous" ||
                fail 'existing trixie suite includes an unsupported architecture or component'
            break
        done
        cp -a --reflink=auto -- "$repository/$release_path/." "$stage/$release_path/" ||
            fail 'could not stage the existing suite'
    fi
    for directory in main "$index_path" "$index_path/by-hash" "$index_path/by-hash/SHA256"; do
        [[ ! -L $stage/$release_path/$directory ]] || fail "unexpected suite symlink: $directory"
    done
    mkdir -p -- "$stage/$release_path/$index_path/by-hash/SHA256" ||
        fail 'could not create the index hash directory'
    rm -f -- "$stage/$release_path/"{Release,InRelease,Release.gpg,"${indexes[0]}","${indexes[1]}"} ||
        fail 'could not replace the old staged metadata'

    local existing_pool="$repository/$pool_path"
    destination="$existing_pool/$filename"
    if [[ -e $destination || -L $destination ]]; then
        [[ -f $destination && ! -L $destination ]] ||
            fail "invalid archive at $pool_path/$filename"
        if ! cmp -s -- "$incoming" "$destination"; then
            [[ $force == 1 ]] ||
                fail "different archive already exists at $pool_path/$filename. Use pkg push -f to replace it."
            existing_identity=$(dpkg-deb -f "$destination" Package Version Architecture) ||
                fail "could not read the identity of $pool_path/$filename"
            incoming_identity=$(dpkg-deb -f "$incoming" Package Version Architecture) ||
                fail 'could not read the identity of the uploaded archive'
            [[ $existing_identity == "$incoming_identity" ]] ||
                fail "archive identity differs at $pool_path/$filename"
        fi
    fi

    # Keep the same relative paths while indexing existing archives without copying them.
    if [[ -e $existing_pool || -L $existing_pool ]]; then
        [[ -d $existing_pool ]] || fail "invalid package pool at $existing_pool"
        find "$existing_pool/." \( -type f -o -type l \) -name '*.deb' -print0 > "$stage/archives" ||
            fail 'could not list the existing package pool'
        while IFS= read -r -d '' archive; do
            relative=${archive#"$existing_pool/./"}
            [[ $relative != "$filename" ]] || continue
            architecture=$(dpkg-deb -f "$archive" Architecture) ||
                fail "could not read the architecture of $pool_path/$relative"
            [[ $architecture == amd64 || $architecture == all ]] || continue
            destination="$stage/$pool_path/$relative"
            mkdir -p -- "${destination%/*}" && ln -s -- "$archive" "$destination" ||
                fail "could not stage $pool_path/$relative for indexing"
            records=$((records + 1))
        done < "$stage/archives"
    fi
    mv -- "$incoming" "$stage/$pool_path/$filename" || fail 'could not stage the uploaded package for indexing'

    cd -- "$stage" || fail 'could not enter the metadata staging directory'
    dpkg-scanpackages --multiversion --hash sha256 "$pool_path" > "$release_path/${indexes[0]}" ||
        fail 'could not generate the Packages index'
    index_count=$(awk '/^Package: / { count++ } END { print count + 0 }' "$release_path/${indexes[0]}") ||
        fail 'could not read the Packages index'
    [[ $index_count == "$records" ]] || fail "expected $records package records, indexed $index_count"
    gzip -n -c -- "$release_path/${indexes[0]}" > "$release_path/${indexes[1]}" ||
        fail 'could not compress the Packages index'

    release="$release_path/Release"
    release_date=$(date -Ru) || fail 'could not determine the Release date'
    {
        printf 'Suite: trixie\nCodename: trixie\nArchitectures: amd64\nComponents: main\n'
        printf 'Date: %s\n' "$release_date"
        printf 'Acquire-By-Hash: yes\nSHA256:\n'
    } > "$release" || fail 'could not write Release metadata'
    for entry in "${indexes[@]}"; do
        digest_line=$(sha256sum < "$release_path/$entry") && bytes=$(stat -c %s -- "$release_path/$entry") ||
            fail "could not checksum $entry for Release"
        digest=${digest_line%% *}
        destination="$release_path/$index_path/by-hash/SHA256/$digest"
        if [[ -e $destination || -L $destination ]]; then
            [[ -f $destination && ! -L $destination ]] && cmp -s -- "$release_path/$entry" "$destination" ||
                fail "invalid retained index hash $digest"
        else
            ln -T -- "$release_path/$entry" "$destination" ||
                fail "could not stage the hash for $entry"
        fi
        printf ' %s %s %s\n' "$digest" "$bytes" "$entry" >> "$release" ||
            fail 'could not write Release checksums'
        pkg_debug push.metadata_index "$entry"
    done
    pkg_debug push.metadata_packages "$index_count"
    pkg_debug push.metadata_release "$stage/$release"
    printf '%s\n' "$filename"
)
