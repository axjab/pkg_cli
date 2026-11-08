# Remote package publication. Loaded with the shared diagnostics.
set -euo pipefail
umask 022

fail() {
    pkg_push_result 31 "pkg: $1"
    exit 1
}

repository=${HOME:?target HOME is not set}
[[ $repository == /* && -d $repository ]] || fail "invalid target home: $repository"
cd -- "$repository" || fail "cannot access target home: $repository"
pkg_debug push.repository "$repository"
command -v dpkg-scanpackages >/dev/null ||
    fail 'required tool missing on target: dpkg-scanpackages (install the dpkg-dev package)'
for tool in gpg awk cat chmod cmp cp date dpkg-deb find flock gzip ln mkdir mktemp mv rm sha256sum stat; do
    command -v "$tool" >/dev/null || fail "required tool missing on target: $tool"
done
probe_dir=$(mktemp -d -- "$repository/.pkg-preflight.XXXXXXXX") ||
    fail "cannot write to repository directory: $repository"
trap cleanup_push EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

printf 'write probe\n' > "$probe_dir/write" || fail 'cannot write in target home'
mv -- "$probe_dir/write" "$probe_dir/renamed" || fail 'cannot rename in target home'
rm -- "$probe_dir/renamed" || fail 'cannot remove files in target home'

sign_release() {
    local release_dir="$probe_dir/dists/trixie"
    key_home=${GNUPGHOME:-$HOME/.gnupg}
    gpg_cmd=(gpg --no-options --batch --no-tty --pinentry-mode error)
    verification_key="$probe_dir/verification.gpg"
    # Verification uses only the key that APT clients would be given.
    verify_cmd=("${gpg_cmd[@]}" --homedir "$probe_dir" --no-auto-key-retrieve --no-autostart)
    public_key="$repository/apt-signing-key.asc"
    if [[ -e $public_key || -L $public_key ]]; then
        [[ -f $public_key ]] || fail "invalid public signing key file: $public_key"
        [[ -d $key_home ]] || fail "restore the GPG keyring for the existing repository public key at $public_key"
        keys=$("${verify_cmd[@]}" --quiet --with-colons --show-keys "$public_key") ||
            fail "could not read the repository public key: $public_key"
        fingerprints=$(awk -F: '$1 == "pub" { primary = 1; next }
            primary && $1 == "fpr" { print $10; primary = 0 }' <<< "$keys")
    else
        for signature in "$repository"/dists/*/{InRelease,Release.gpg}; do
            if [[ -e $signature || -L $signature ]]; then
                fail "signed repository requires its public key at $public_key"
            fi
        done
        public_key=
        keys=
        if [[ -e $key_home || -L $key_home ]]; then
            [[ -d $key_home ]] || fail "invalid GPG keyring directory: $key_home"
            keys=$("${gpg_cmd[@]}" --with-colons --list-secret-keys) ||
                fail 'could not read the target GPG keyring'
        fi
        # Bootstrap only when the unsigned repository account has no secret keys.
        if ! awk -F: '$1 == "sec" { found = 1 } END { exit !found }' <<< "$keys"; then
        # An explicitly configured GNUPGHOME may not be created by GPG.
        if [[ ! -d $key_home ]]; then
            mkdir -m 700 -- "$key_home" || fail "could not create the GPG keyring at $key_home"
        fi
            gpg --no-options --batch --no-tty --pinentry-mode loopback --passphrase '' \
                --quick-generate-key 'pkg APT Repository' ed25519 sign never ||
                fail 'could not create the repository signing key'
            pkg_debug push.signing_key_created true
            keys=$("${gpg_cmd[@]}" --with-colons --list-secret-keys) ||
                fail 'could not read the new repository signing key'
        fi
        fingerprints=$(awk -F: '$1 == "sec" { signing = ($12 ~ /S/); next }
            signing && $1 == "fpr" { print $10; signing = 0 }' <<< "$keys")
    fi
    [[ -n $fingerprints && $fingerprints != *$'\n'* ]] ||
        fail 'expected exactly one repository signing key'
    fingerprint=$fingerprints
    pkg_debug push.signing_fingerprint "$fingerprint"

    if [[ -n $public_key ]]; then
        "${verify_cmd[@]}" --output "$verification_key" --dearmor "$public_key" ||
            fail 'could not prepare the repository public key for verification'
    else
        "${gpg_cmd[@]}" --armor --output "$probe_dir/apt-signing-key.asc" --export "$fingerprint" ||
            fail 'could not export the public signing key'
        chmod 0644 -- "$probe_dir/apt-signing-key.asc" || fail 'could not make the public signing key readable'
        "${verify_cmd[@]}" --output "$verification_key" --dearmor "$probe_dir/apt-signing-key.asc" ||
            fail 'could not prepare the exported public key for verification'
    fi
    [[ -s $verification_key ]] || fail 'verification key is empty'
    "${gpg_cmd[@]}" --local-user "$fingerprint" --output "$release_dir/InRelease" \
        --clearsign "$release_dir/Release" ||
        fail "could not sign without a prompt using $fingerprint"
    if ! verification=$("${verify_cmd[@]}" --no-default-keyring --keyring "$verification_key" \
        --verify "$release_dir/InRelease" 2>&1); then
        printf '%s\n' "$verification" >&2
        fail "signature verification failed for $fingerprint"
    fi
    chmod 0644 -- "$release_dir/InRelease" || fail 'could not make the signed Release readable'
    pkg_debug push.signature_verified true
    pkg_push_result 32 "Signed Release verified (GPG key $fingerprint)"
}

expected_checksum=$1
staged_archive="$probe_dir/package.deb"
pkg_debug push.staged_archive "$staged_archive"
cat > "$staged_archive" || fail 'could not stage the incoming archive'
digest_line=$(sha256sum < "$staged_archive") || fail 'could not hash the staged archive'
received_checksum=${digest_line%% *}
[[ $received_checksum == "$expected_checksum" ]] ||
    fail 'archive SHA-256 mismatch; the transfer is incomplete or the source changed'
pkg_debug push.transfer_verified true
# Hold the write lock through cleanup, including rollback of a failed activation.
exec 9<.
flock -x -w 30 9 || fail 'could not lock the repository for publication'
for directory in pool pool/main dists dists/trixie; do
    [[ ! -L $repository/$directory ]] || fail "unexpected repository symlink: $directory"
done
filename=$(prepare_metadata "$repository" "$probe_dir" "$staged_archive" 9<&-)
# GPG must not inherit the repository lock.
sign_release 9<&- </dev/null
activate_release "$filename"
printf '%s\n' "$received_checksum"
