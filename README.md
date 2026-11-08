# APT bootstrap

Add a repository by creating `repos/<name>.sh`, then run `./do/compile`.
The compiler embeds every `repos/*.sh` file in alphabetical order into
`install.sh`. Publish that generated file at your existing `/install` URL.
Your existing single-file upload procedure can continue to publish it.

```sh
cd provision
./do/compile
# Publish install.sh using your existing deployment procedure.
```

On a new Debian 13 amd64 machine, run as a normal user with sudo.

```sh
curl -fsS https://apt.alj.cx/install | sh
sudo apt install core
# Or install desktop-pkg, which depends on core.
```

For local setup from this directory, run `sh bootstrap.sh`.
The bootstrap requires curl, working HTTPS certificates, sudo, and standard
Debian utilities including flock. It configures sources and runs one strict
APT update. Package installation remains a separate command.

## Adding a repository

Each module calls the shared helper once. Arguments are name, repository URL,
suite, components, signing-key URL, key format (`asc` or `gpg`), and optionally
a SHA-256 digest of the exact downloaded key bytes.

```sh
#!/bin/sh
add_repository example https://packages.example.org/debian stable main \
    https://packages.example.org/key.asc asc
```

Use the vendor's actual values. Quote wildcards such as Charm's `'*'`.
Modules run in separate subshells as the invoking user and should only call
`add_repository`. Do not put sudo, apt update, or package installation in them.
Only reviewed local modules should be compiled into the installer.

Included modules configure your repository, Charm, Docker, eza, Gopass,
Mullvad, and Yazi. The supplied private-repository URL and key checksum are
preserved. Third-party keys are obtained over HTTPS without a pinned digest
unless you add the optional seventh argument. Keys are scoped with Signed-By.

## Existing machines and failures

All downloads and source generation finish before system configuration starts.
Activation uses the existing bootstrap lock. Identical configurations are reused.
Conflicting files and symlinks are rejected. A failed activation or APT refresh
removes only files newly created by this run, retaining pre-existing files.

This version uses Deb822 `.sources` files and keys under `/etc/apt/keyrings`.
Machines configured by the old snippets may have `.list` files or different key
paths. The bootstrap reports those conflicts instead of overwriting them.
Review and migrate those entries before retrying. It does not detect duplicates
under arbitrary unrelated filenames or in the main sources.list.

Removing a module excludes it from future compiled installers. It does not
remove an already configured repository from existing machines. Key changes
also require reviewing the reported conflict before replacing an installed key.

Compile and redeploy after every module change. Editing `install.sh` directly
will be overwritten by the next compile. The original bootstrap remains
restricted to Debian 13 trixie on amd64. Ghostty is not configured by the seven
supplied modules, so its package availability still needs resolving before core
can be guaranteed installable on a clean machine.

## Validation

Shell syntax, automatic inclusion of new modules, and preservation of the prior
compiled installer on syntax failure were checked. Isolated filesystem tests
passed for activation, identical reruns, conflicting files, symlinks, and rollback
following a simulated APT failure. Root ownership and APT were mocked in those
tests.

A live APT refresh using isolated lists and sources accepted signed metadata
from your repository, Charm, Docker, eza, Gopass, and Yazi. Mullvad returned an
HTML “Site Unavailable” page for both the key and InRelease in this environment,
so full seven-repository validation remains incomplete. The bootstrap now rejects
that invalid armored key before activation. A clean-machine package installation
was not performed.
