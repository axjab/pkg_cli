# pkg_cli — development handoff

Updated 2026-11-08. This replaces the earlier handoff whose next task was implementing `pkg push`.

## TLDR for the maintainer

Publication and client installation work end to end. `pkg push helloworld` published signed APT metadata; a disposable Debian trixie container ran the public installer, installed `helloworld` by name, and successfully executed its `tty-notify` command.

Next, in order: integrate Charmbracelet Gum into the CLI, package the compiled `pkg` executable with Gum as an APT dependency, then add package-content inspection with color-coded categories. Preserve the working publication and bootstrap paths.

The latest tree still places the canonical installer at root `install.sh`, with another copy in `dist/`. `do/update-install-script` now exists. Moving the installer out of root was discussed but is not reflected in the latest tree. Do not silently assume that move or deployment verification has happened.

## 1. Resume here

**TLDR:** Inspect current sources, then implement the first Gum increment. Do not restart publication development.

Read the current `do/compile`, handlers and shared helpers under `lib/`, tests, and `do/update-install-script`. Use the maintainer's current checkout or latest supplied files as the implementation baseline. A directory listing proves file presence, not implementation contents. Earlier ZIPs are recovery material and may lack newer changes.

The next three authorized tasks are:

1. Refactor scripts to use **Gum by Charmbracelet** as a dependency.
2. Build a Debian package for **pkg_cli**, containing the compiled **`pkg`** executable and declaring **`gum`** as a dependency.
3. Add **`pkg inspect` or `pkg ls <package>`** to show the contents of a selected package, with categories distinguished by color: executables, dependencies, and other applicable content. This is not another listing of workspace packages.

Start with a small useful Gum integration through the normal CLI. Preserve noninteractive behavior, meaningful exit statuses, and machine-readable stdout. Consult current official Gum documentation when implementing; no Gum version, minimum version, or installation source has been verified in this handoff.

### Acceptance boundaries for the next tasks

| Task | Required result and checks |
|---|---|
| Gum integration | Existing interactive selection/output uses Gum where useful; cancellation and empty selection do not mutate state; explicit noninteractive commands continue to work; redirected output and `NO_COLOR` remain usable. Document any changed runtime prerequisites. |
| pkg_cli Debian package | Package installs a runnable `pkg` independent of the checkout and declares Gum in dependency metadata. Establish how a clean client resolves `gum` before claiming installation works. A `Depends` field alone does not make the dependency available in APT. Test installation and removal in a disposable container. |
| Package inspection | Select one package and report its payload and declared dependencies, distinguishing categories with both labels and color. Preserve bare `pkg ls` as the workspace package-name listing. Test empty, missing, and ordinary packages plus redirected output. |

The Debian package name is not settled: `pkg_cli` is the project name, not a literal Debian package identifier to copy without validation. `pkg-cli` is a possible name; check current packaging and avoid collisions before choosing. `/exe/pkg` is the existing development compilation destination; the packaged executable's installation path must be chosen explicitly and tested on a normal client.

The inspection command spelling and whether it inspects staged packages, built archives, or installed packages remain unresolved. Inspect the current data model and choose the smallest coherent initial scope, stating it clearly. Do not silently claim all three. Dependencies are metadata, not payload files, and should appear as a distinct category.

Do not make the zero-argument repository bootstrap install Gum or pkg automatically merely to support these development tasks. Users choose packages afterward with APT.

## 2. Collaboration and delivery workflow

**TLDR:** Implement, test, deliver a small overlay, then use the maintainer's real-environment feedback.

- The maintainer defines the product and runs production-like tests. Make routine engineering decisions without repeated permission questions. Ask only when a consequential choice truly cannot be inferred.
- Keep responses short: what changed, what was tested, limitations, and commands to try.
- Inspect actual source before editing. Never claim to have changed the maintainer's checkout when only an artifact was prepared.
- Deliver complete replacement/new files in a downloadable ZIP at checkout-relative paths, without an enclosing directory. Include required helpers and preserve executable modes.
- Include only changed files and necessary dependencies. Do not overwrite newer unrelated work with a stale full snapshot. Do not include credentials, `.pkg` data, caches, generated archives, or unrelated `_tmp` material.
- A ZIP cannot delete files by omission. State required removals or moves explicitly.
- Test handlers and compiled behavior as appropriate. State exactly which tests ran and whether SSH/GPG were real or simulated.
- Maintainer extracts the overlay, runs `do/test` and `do/compile` (or `bash do/compile`), then tests the normal `pkg` interface. Fix a failed checkpoint before advancing.
- Do not run production publication, change `/exe/pkg` on the maintainer's machine, or post issues unless that execution is part of the requested work.

Priority: latest maintainer instruction → actual source for existing behavior → this handoff → older documents. Current source tells us what exists; instructions define requested changes.

## 3. Current tree and source ownership

**TLDR:** Development utilities are in `do/`; runtime code is in `lib/`; the installer is still at root.

Maintainer-supplied tree at handoff time, with generated cache entries and historical `_tmp` leaves condensed:

```text
.
├── dist/
│   ├── helloworld_0.0.0_all.deb
│   └── install.sh
├── do/
│   ├── compile
│   ├── new-issue
│   ├── start-os
│   ├── test
│   └── update-install-script
├── doc/
│   ├── INSTALLATION_SCRIPT_ENGINEERING_BLUEPRINT.md
│   ├── INSTALLATION_SCRIPT_ENGINEERING_FOR_HUMAN.md
│   └── PKG-CLI-HANDOFF.md
├── Dockerfile
├── install.sh
├── lib/
│   ├── hosts.sh
│   ├── package.sh
│   ├── pkg-add
│   ├── pkg-build
│   ├── pkg-create
│   ├── pkg-host
│   ├── pkg-hosts
│   ├── pkg-init
│   ├── pkg-ls
│   ├── pkg-ping
│   ├── pkg-push
│   ├── push-metadata.sh
│   ├── push-output.sh
│   ├── push-publish.sh
│   ├── push-readiness.sh
│   └── workspace.sh
├── README.md
├── tests/
│   ├── __pycache__/                 # generated
│   ├── test_pkg_add.py
│   ├── test_pkg_build.py
│   ├── test_pkg_create.py
│   ├── test_pkg_hosts.py
│   └── test_pkg_push.py
└── _tmp/                           # historical/reference material
    ├── apt-sources/
    ├── build/
    ├── dist/
    ├── lib/
    ├── lib.old/
    ├── metapackages/
    ├── recommended-structure.txt
    ├── reference/
    ├── repositories/
    └── scripts/
```

The full supplied listing reports 26 directories and 76 files. `.pkg/` does not appear in that listing; previous command output confirms workspace state under `.pkg`. Do not infer it was removed from a non-hidden tree listing.

`lib/` is bundled runtime code. Do not move the bootstrap installer there simply to clean the root: it would become part of the compiled payload. A new root directory just for one installer was rejected as no improvement. Moving it to `do/install.sh` was discussed, but the newest tree takes precedence: it remains at root. Inspect all references before any future move, including `dist`, container mounts, and deployment script paths.

## 4. Implemented CLI contract

**TLDR:** Keep existing local workflows, discovery, selection, output, and preservation behavior intact.

### Compile and tests

`do/compile` takes no arguments, resolves the project root relative to its own location, bundles `lib/`, and writes `/exe/pkg` with executable permissions. The fixed development destination is intentional. Handlers locate helpers relative to themselves, not the caller's working directory. The compiled CLI must work away from the checkout.

`do/test` must similarly anchor to its own parent project directory before discovery. A naked `python3 -m unittest discover -s ../tests -v` depends on the caller's working directory and caused discovery failures. The accepted approach is to enter the project root and discover `tests` there. Verify the current scripts from both root and another directory when changing them.

### Commands and selection

- `pkg init`: creates or reuses the nearest workspace; does not implicitly create a package or run Git initialization.
- `pkg ls`: sorted workspace package names, one per line; an empty workspace produces empty stdout.
- `pkg create <name>`: empty package under `.pkg/packages/<name>/`; defaults include version `0.0.0`, architecture `all`, section `utils`, priority `optional`, and placeholder maintainer/description.
- `pkg add <executable> [to <package>]`: stages into package `bin/`; short form `<executable> <package>` also exists. Source paths are caller-relative. Preserve conflicting existing content.
- `pkg build [<package>] [to <directory>]`: builds and verifies a local archive, defaults to workspace `dist/`, prints its absolute path, preserves conflicting archives, and rejects output inside managed `.pkg/` storage.
- `pkg host add <host>`: offline workspace-local registration in `.pkg/hosts`; `pkg host` and `pkg hosts` list registrations.
- `pkg ping [host]`: explicit targets work outside a workspace; omitted target uses registered-host selection. Preserve SSH status including 255.
- `pkg push`: selects a built local package and host, performs readiness/transfer/metadata/signing, then publishes. The confirmed invocation is `pkg --debug push helloworld`. Inspect handler help for exact optional host syntax before changing it.

Nearest-workspace discovery is Git-inspired and uses physical parent paths. A malformed nearest marker must stop discovery. Preserve existing symlink restrictions. Do not fall back to unrelated remembered workspaces.

Omitted selection infers the sole candidate. Multiple candidates prompt only in a terminal; noninteractive ambiguity fails with explicit-selection guidance. Unknown packages should point to `pkg create`. Literal `localhost` uses direct execution; do not silently treat every localhost-like SSH alias as the current identity.

Use `pkg help`, `pkg help <command>`, and global `pkg --debug <command>`. Preserve current argument conventions and meaningful statuses. Diagnostics/debug go to stderr; stdout stays useful in scripts. Honor `NO_COLOR` and redirected-output behavior.

## 5. Publication status and operator workflow

**TLDR:** Signed publication is implemented and was confirmed live by the maintainer.

The completed checkpoints were readiness, verified transfer, staged metadata, signed activation, and client installation. Earlier messages saying “No package was published” were intermediate stages, not current success criteria.

Typical workflow from a package workspace:

```sh
pkg build helloworld
pkg --debug push helloworld
```

The confirmed live SSH alias is `apt`. The target account's home is `/srv/pkg/apt` and is the repository root. Older `pkg-host`, `apt@old_shrine`, or `~/public/apt` examples are historical; use actual SSH configuration. Package building remains local. Push must not implicitly build or upload every archive in `dist`.

The successful output included:

```text
pkg.debug.push.transfer_verified=true
pkg.debug.push.metadata_packages=1
pkg.debug.push.signature_verified=true
Signed Release verified (GPG key 17807F5DED23C905CCD81EBD258FB9551F4E7C7B)
pkg.debug.push.live_release=/srv/pkg/apt/dists/trixie/InRelease
Published helloworld_0.0.0_all.deb to apt (trixie/amd64)
```

That fingerprint is an observed signing identity, not a mandate to hardcode it into new code. An earlier generated fingerprint was superseded. The installer's pinned SHA-256 is a digest of public-key file bytes, not the GPG fingerprint.

Public layout:

```text
/srv/pkg/apt/
├── apt-signing-key.asc
├── dists/trixie/
│   ├── InRelease
│   ├── Release
│   └── main/binary-amd64/
│       ├── Packages
│       ├── Packages.gz
│       └── by-hash/SHA256/<index-digests>
└── pool/main/<package>_<version>_<architecture>.deb
```

The initial distribution/component/client architecture are `trixie/main/amd64`; architecture-independent `all` packages are indexed for amd64 clients. Preserve unrelated packages when regenerating metadata.

The delivered publication design stages work, checks transferred SHA-256, generates indexes and Release, signs and verifies InRelease, and activates prepared metadata. Atomic trixie-directory exchange and rollback were part of that implementation; inspect current `push-publish.sh` and its tests before modifying those guarantees. Successful logs do not establish every interruption/concurrency case or whole-repository atomicity.

The maintainer explicitly requested automatic signing-key provisioning inside push instead of a manual SSH prerequisite. The requested new-key command uses GPG batch mode, an empty passphrase, `ed25519`, signing capability, and no expiration, with identity `pkg APT Repository`. Preserve safe handling of existing keys and ambiguous identities; never regenerate or rotate an established signing key silently. Inspect the current readiness helper for exact provisioning conditions.

## 6. Public serving and bootstrap workflow

**TLDR:** Bootstrap makes packages available by name; it does not choose or install packages.

The live bootstrap URL is **https://apt.alj.cx/install**. It was tested by the maintainer, not re-probed during this documentation update.

Client workflow as a normal user with sudo:

```sh
curl -fsS https://apt.alj.cx/install | sh
sudo apt install helloworld
```

Installer contract:

- No arguments and no desktop/gaming/headless profiles.
- Configure the repository public key and APT source, then update APT metadata.
- Pin the expected public-key SHA-256 and scope repository trust through its keyring/source configuration.
- Require publisher configuration of the URL and pinned digest; the template initially failed with “the publisher must configure the pinned key SHA-256.” Do not restore an unconfigured template over the live configured script.
- Current installer requires a normal user and uses sudo for system changes; it rejected direct root execution in a container.
- End with informational guidance such as `sudo apt install <package>`. Package selection belongs to the host/operator.

Use the relevant parts of `doc/INSTALLATION_SCRIPT_ENGINEERING_BLUEPRINT.md`; implementing that entire document is not required. Preserve a simple shell bootstrap rather than adding Gum as a bootstrap prerequisite.

### Caddy boundary

The serving design exposes only `dists`, `pool`, the public signing key, and the bootstrap route. `dists` and `pool` have directory browsing with dotfiles hidden. Unmatched requests show a minimal HTML navigation menu linking repository metadata, packages, signing key, and installer.

The bootstrap is separately deployed under `/srv/pkg/bootstrap/install.sh`. The exact current Caddy `/install*` mapping should be inspected before editing; the tested public endpoint is `/install`. Do not assume `/install.sh` is also a verified endpoint.

Do not broaden the document root to serve all of `/srv/pkg/apt`. The target account's GPG state, SSH state, staging directories, and any backup state must remain private. Hiding dotfiles alone is not the security boundary. The server signing key has no passphrase for unattended use, making filesystem/account isolation particularly important. This handoff records working publication, not a completed independent security audit.

### Installer deployment

The latest tree contains **`do/update-install-script`**. Its contents and successful post-upload verification were not supplied in the last update; existence is confirmed, exact behavior is not.

The agreed deployment direction is strictly local source → remote bootstrap file. Proposed configurable defaults:

| Setting | Default |
|---|---|
| `INSTALL_HOST` | `old_shrine` |
| `INSTALL_PATH` | `/srv/pkg/bootstrap/install.sh` |
| `INSTALL_URL` | `https://apt.alj.cx/install` |
| Local source in latest tree | root `install.sh` |

The proposed workflow validates with `sh -n`, uses rsync checksum comparison and mode `0644` to replace the one remote file, downloads the public URL into temporary storage, compares bytes with `cmp`, cleans up, and only then reports publication verified. Use safe remote argument handling. Do not use destructive directory synchronization or copy back from the server.

A previous proposed snippet referenced `do/install.sh`; that conflicts with the latest tree. Resolve the source path against the actual checkout before running deployment. `dist/install.sh` is another copy, not an established second source of truth. No continuous synchronization, scheduled reconciliation, or automatic trigger is confirmed; a deployment helper alone does not mean the file is always synchronized.

## 7. Disposable-container verification

**TLDR:** The maintainer confirmed fresh-client installation and executable use.

`Dockerfile` and `do/start-os` support a disposable Debian trixie environment with curl, a normal `pkgtest` user, and sudo already configured. Earlier guidance used local image tag `aptt`; inspect the current launcher for the actual tag. The launcher should resolve project paths relative to itself, build from the project Dockerfile when its local image is absent, then run an interactive `--rm` container with project `dist/` mounted read-only at `/pkg`.

Do not use `docker build ..` or `$PWD/dist` without first anchoring the working directory: those depend on where the operator invokes `do/start-os`.

Confirmed manual test:

```sh
# On the development host:
do/start-os

# In the disposable container as pkgtest:
tty-notify hi                         # initially: command not found
curl -fsS https://apt.alj.cx/install | sh
sudo apt install helloworld
tty-notify hi                         # delivered=1 failed=0
```

APT fetched trixie InRelease and the amd64 package index from `https://apt.alj.cx`, then installed `helloworld` version `0.0.0`, architecture `all`. Missing dialog/readline frontends produced debconf fallback messages in the minimal container; installation completed.

An earlier 60-test run had one GPG fixture error in `test_sign_and_verification_failure_cleanup` while generating `Test One` for the `--verify` subcase. A fixture fix was delivered during readiness development. Do not claim the latest full suite is green without rerunning it on current sources. Earlier local/simulated checks and live publication are separate evidence.

For the next packaging checkpoint, repeat a clean-container test installing the new CLI package through APT, verify Gum resolves automatically, run `pkg help`, and exercise a local workspace. Avoid installing Gum manually first and thereby masking missing repository dependency support.

## 8. Engineering safeguards and deferred work

**TLDR:** Preserve data and automation contracts while improving the interface.

Runtime handlers are Bash; preserve their strict-mode and quoting conventions. Bootstrap/deployment helpers may use POSIX `sh`; do not insert Bash-only syntax into those scripts. Forward arguments with `"$@"`, preserve caller-relative paths, and use readable validation. Handle SSH/rsync quoting deliberately and never concatenate unchecked inputs into shell programs.

Reuse `workspace.sh`, `package.sh`, `hosts.sh`, and publication helpers rather than inventing parallel abstractions. Keep diagnostics tied to actual operations and do not print secret material. GPG readiness probes must not leak private keys or silently change established trust.

Preserve existing add/build/push conflict behavior: accept identical content where supported and reject conflicting content without overwriting it. Stage changes, clean only owned temporary paths, and avoid destructive operations against the SSH account's home. Add meaningful tests for new failures and behaviors; do not claim mocks prove live SSH or APT behavior.

Deferred: `pkg -C`, a standalone `.deb` publication validator, general remote builds/workspaces, generalized distribution/architecture support, and broad `_tmp` cleanup. None is a prerequisite for the three next tasks. Bootstrap installation is now completed work, not a deferred feature.

`do/new-issue` exists. Prior instructions preferred direct curl to the GitHub API rather than `gh`, targeting `axjab/pkg_cli`; verify destination and authorization before posting. Earlier drafted issues were not confirmed posted.

## 9. Recovery references

**TLDR:** Prefer the current checkout. These are historical recovery artifacts, not guaranteed current full snapshots.

- [Publication implementation overlay](https://chatgpt.com/library?file_id=libfile_50ded3afa0648191994321543050dd03&account_id=personal)
- [Metadata checkpoint overlay](https://chatgpt.com/library?file_id=libfile_b562b5567dd08191b4f09086ecfa3cb9&account_id=personal)
- [Transfer checkpoint overlay](https://chatgpt.com/library?file_id=libfile_07f65ae357748191857893fb3dc5aa47&account_id=personal)
- [Readiness fixture fix](https://chatgpt.com/library?file_id=libfile_aebc29778d948191b55b46f93a3197b9&account_id=personal)
- [do/compile overlay](https://chatgpt.com/library?file_id=libfile_92b4b48040588191874ff6a132d89bc7&account_id=personal)
- [Installer artifact](https://chatgpt.com/library?file_id=libfile_f972c6a3f8548191a2387c19e7d94b74&account_id=personal) — may be the unconfigured template; preserve the publisher's current values.
- [Disposable-container Dockerfile artifact](https://chatgpt.com/library?file_id=libfile_96f0d242295c81918e1b9d5c7689668b&account_id=personal)

This update changes documentation only. It does not modify the checkout, deploy an installer, install Gum, build the new CLI package, or implement inspection. Resume with the current sources and the three tasks in section 1.
