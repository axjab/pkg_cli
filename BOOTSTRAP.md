# Operating the APT bootstrap

Extract this ZIP into the project root. It supplies lib/bootstrap.sh, do/compile,
the seven repos/*.sh definitions, and the generated srv/install.sh.

Delete obsolete root install.sh and bootstrap.sh files from earlier layouts, if present. If you installed the
earlier provision/ directory, remove that old bootstrap copy after moving to
this root layout. The ZIP cannot remove obsolete files automatically.

## Files to edit

- repos/*.sh contains one repository definition per file, including pkg.sh for apt.alj.cx.
- lib/bootstrap.sh contains the shared setup logic and loads those definitions locally.
- do/compile generates srv/install.sh with all definitions embedded.
- srv/install.sh is the standalone file to serve at your existing /install URL.
  The compiler sets it to mode 0444.

repos/repos.bak/ is ignored because discovery only reads direct repos/*.sh files.
Keep that backup directory if wanted.

## Normal workflow

From the project root, add or edit a repository script, then compile.

```sh
./do/compile
```

Publish srv/install.sh at https://apt.alj.cx/install using your existing deployment
process. Configure that process to copy srv/install.sh instead of root install.sh
and preserve mode 0444 if you also require the deployed file to be read-only.
Compilation only generates the local file.

On a new machine, run as a normal user with sudo.

```sh
curl -fsS https://apt.alj.cx/install | sh
sudo apt install core
```

For desktop dependencies, install desktop-pkg, which depends on core.

To run the standalone output locally, use sh because mode 0444 omits execute bits.

```sh
sh ./srv/install.sh
```

## New repository example

Create repos/example.sh with the vendor's actual values.

```sh
#!/bin/sh
add_repository example https://packages.example.org/debian stable main \
    https://packages.example.org/key.asc asc
```

Arguments are name, repository URL, suite, components, signing-key URL, key format
(asc or gpg), and optional SHA-256 of the exact key bytes.
These modules run with the shared add_repository helper. They should only prepare
their repository. The generated installer performs activation and one final apt update.

## Current limits and verification

The installer targets Debian 13 trixie on amd64 and requires curl, HTTPS
certificates, sudo, and standard Debian utilities. Existing conflicting source
or key files require migration before rerunning. Definitions removed from repos/
are excluded from the next build but remain configured on existing machines.

Tests covered compilation from another working directory, backup exclusion,
new module discovery, read-only rebuilding, and preservation of the previous
output after a syntax failure. Isolated tests with mocked APT and ownership
checks covered activation, reruns, conflicts, symlinks, and failure rollback.

Earlier live APT verification accepted six repositories. Mullvad returned HTML
error pages in this environment and remains unverified. Ghostty's repository
is absent from the supplied definitions, so a full core installation on a clean
machine remains unverified. The supplied personal repository key checksum is
preserved. Third-party key downloads use HTTPS and scoped Signed-By references,
with an optional checksum available in each definition.
