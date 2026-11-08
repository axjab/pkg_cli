# pkg_cli — development handoff

Updated 2026-11-08 at session close. Supersedes the earlier handoff that listed Gum integration, CLI packaging, and package inspection as future tasks.

## TLDR for the maintainer

The CLI now manages package metadata, dependencies, executables, configuration, services, assets, and lifecycle files. It provides categorized inspection, numbered package selection, direct control-file editing, version reporting, and force replacement for add/build/push. The maintainer demonstrated the complete release cycle through APT, upgrading the installed `pkg-cli` from **0.2.1 to 0.2.2** and confirming `pkg version` prints **0.2.2**.

All package definitions belong under `.pkg/`. The sole definition for this tool is `.pkg/packages/pkg-cli/DEBIAN/control`. The accidentally introduced `packaging/pkg-cli.control` was superseded and must not return. The command's version is embedded when compiled, so changing control metadata requires recompilation and restaging before building a release.

The README now begins with a plain-English release walkthrough based on the successful demo. The main unfinished engineering work is the legacy test suite: the newer Bash suite passed during development, but the old suite still has unmigrated expectations and environment-dependent GPG failures. Do not claim all tests pass.

## 1. Resume from current sources

**TLDR:** Obtain the maintainer's current checkout before changing code. The successful installed release is 0.2.2; the assistant's older source snapshot still has important differences.

The next session should first establish the current source and test baseline. No additional feature was selected at session close. Do not restart completed Gum, inspection, or publication development.

Known source divergence:

| Item | Maintainer's latest evidence | Assistant's inspected snapshot |
| --- | --- | --- |
| Release version | 0.2.2 successfully installed through APT | Canonical control still at 0.1.2 |
| Compile output | `do/compile` reports `Built ./pkg` | Defaults to `/exe/pkg`; supports `PKG_COMPILE_DIR` |
| Runtime version | `pkg version` prints 0.2.2 after APT upgrade | Reads the control file bundled at compile time |
| Package publishing | Actual SSH/GPG/APT cycle succeeded | Force and rollback checks included local simulations |

The repository is `axjab/pkg_cli`; the Debian package is `pkg-cli`; the executable is `pkg`. The maintainer's checkout is `/home/i/src/pkg-cli`. The assistant worked in `/workspace/scratch/6ce39f8debf4/repo`, originally based on commit `13eb69b184e867e69bf88db1a6e2c22ad724a3c4`, with substantial cumulative uncommitted changes. That snapshot is recovery material, not proof of the maintainer's current contents.

Suggested next maintenance checkpoint:

1. Read current compile, version, control, and test entry points.
2. Reconcile compile destination documentation with the actual implementation.
3. Run the current test suites with bounded execution and identify every remaining failure.
4. Migrate obsolete test expectations while preserving safety assertions and fixing real regressions.
5. Reconfirm a disposable-client installation when changing packaging or dependency handling.

## 2. Product and collaboration constraints

**TLDR:** Preserve the action-first CLI, use Bash for implementation, and deliver small, reviewable changes.

- The model is intelligent, context-sensitive, and action-first. Ambiguity among packages, dependencies, executables, configuration, services, and other components prompts interactively.
- Prefer positional words and explicit categories over new double-dash options. The requested `-f` flag is supported for add, build, and push.
- Runtime work and new regression scripts should be Bash. Existing Python tests remain migration work; their presence is not permission to rewrite the tool in Python.
- Package definitions and workspace state belong in `.pkg/`. Compiled output and distributable archives can live outside it. Do not create another package manifest directory.
- Use actual source before editing. Preserve the maintainer's metadata and local changes. Never overwrite their version or identity with placeholders from an old artifact.
- Make routine implementation decisions without repeated approval questions. If the proposed command schema has a material contradiction, surface it before implementing an incompatible interpretation.
- Source deliveries are ZIP overlays with checkout-relative paths and no enclosing directory. Include required helpers and executable permissions. A ZIP cannot remove a file by omission; state required deletions.
- Provide direct downloadable file links. The maintainer explicitly asked for the README file after receiving only a Library link.
- Do not claim edits to the maintainer's machine, successful production publication, or green tests based solely on prepared artifacts or mocks.
- Do not publish, rotate signing keys, post issues, or change production hosts without task authorization.

Priority is latest maintainer instructions, then current source for observed implementation, then this handoff, then historical artifacts.

## 3. Implemented command contract

**TLDR:** Metadata and component operations are implemented through the normal `pkg` interface.

| Command | Behavior |
| --- | --- |
| `version` | Print the running CLI's version embedded at compilation |
| `help` | General or command help; `pkg help <command>` |
| `init` | Create/reuse the nearest workspace |
| `new` | Create a package with the full directory skeleton |
| `add` | Add a dependency or staged component; `-f` replaces a conflicting file |
| `mv` | Rename a package, dependency, or staged component |
| `rm` | Remove a package, dependency, or staged component |
| `ls` | List workspace packages or inspect/query a selected package |
| `set` | Mutate metadata, including user-defined fields |
| `get` | Print metadata values |
| `edit` | Open the package's actual `DEBIAN/control` in an editor |
| `build` | Build and verify a local archive; optional `-f` replacement |
| `host` | Define/query workspace publishing hosts |
| `ping` | Check a host using existing behavior |
| `push` | Publish an existing archive and prepare repository/signing boilerplate; optional `-f` replacement |

`create` and `hosts` remain compatibility aliases. `--dep`, `--deps`, and `--executables` also retain compatibility behavior. `new` is the preferred spelling. There is no combined `pkg build push -f` invocation; build and push are separate commands.

Representative syntax:

```bash
pkg new myapp
pkg add executable ./myapp to myapp
pkg add -f ./myapp to myapp
pkg add dependency gum 2.0.2 to myapp
pkg add configuration ./myapp.conf to myapp
pkg add service ./myapp.service to myapp
pkg add asset ./template as usr/share/myapp/templates/default to myapp
pkg add lifecycle ./postinst to myapp
pkg mv executable myapp to myapp-cli in myapp
pkg mv dependency gum to 'gum (>= 2.0.2)' in myapp
pkg rm dependency gum from myapp
pkg rm service myapp.service from myapp
pkg mv package myapp to terminal-tools
pkg ls
pkg ls terminal-tools
pkg ls service in terminal-tools
pkg set version 1.0.0 in terminal-tools
pkg set X-Owner operations in terminal-tools
pkg get X-Owner from terminal-tools
pkg edit terminal-tools
pkg build terminal-tools
pkg host add apt
pkg push terminal-tools to apt
```

Component categories include package, dependency, executable, configuration, service, documentation, asset, desktop, metadata, lifecycle, other, and the special control category. Aliases include dep, exe, config, doc, assets, dependencies, and executables.

### Inference, selection, and safety

A sole package can be inferred. Multiple package candidates prompt with **numbers**, and the operator types a number. The last prompted package name is remembered per workspace/user in `.pkg/.last-package-<uid>`. Enter accepts that choice when still valid. A missing/deleted remembered package provides no default. Enter without a valid default cancels. Invalid nonblank input can be retried. Explicit package arguments do not overwrite the remembered prompt choice.

Package prompts use the numbered plain interface even when Gum is installed. Other target/category menus use Gum where appropriate, with plain behavior under `NO_COLOR`. Noninteractive ambiguity fails with guidance and never relies on a remembered choice to mutate silently.

Paths and familiar suffixes guide component inference. A bare name that can be both a dependency and local file is ambiguous; use `./file` or an explicit category. In automation, specify category, target package, and full package-relative paths when basenames collide.

Nearest-workspace discovery stops at malformed markers. Preserve path traversal checks, symlink restrictions, workspace mutation locking, and the protection of `DEBIAN/control`. Package removal affects staged state; built and published archives are separate. Package renaming updates its directory and Package field but retains payload paths and contents.

## 4. Inspection and skeletons

**TLDR:** `pkg ls <package>` shows metadata once and categorizes all contents. Three infrequently used categories disappear when empty.

Metadata is presented at the top under `DEBIAN/control`. The earlier duplicate `Package` summary plus repeated full control block was removed. Relationships such as Depends appear in the dependency section rather than repeating the same information at the top.

Dependencies are displayed in a terminal-width, column-major grid similar to filesystem `ls`. A versioned relationship remains one cell. Depends entries appear directly under Dependencies; other relationship types retain their labels. Width comes from COLUMNS, terminal information, or a fallback.

Categories have distinct heading colors and matching secondary entry colors. Documentation, desktop assets, and other are hidden when empty. All remaining categories are displayed even when empty. Directory skeletons alone do not count as real entries. Redirected output and `NO_COLOR` remain plain.

Service paths are classified before generic configuration paths, so `etc/init.d` and systemd paths appear as services. Control metadata and lifecycle scripts have separate categories. Documentation includes doc/man/info, and desktop assets include launchers/icons and related shared paths.

`pkg ls <category> in <package>` produces plain component paths or dependency entries. An exact package name takes precedence over a category name in `pkg ls <name>`. Bare `pkg ls` still prints workspace package names.

`pkg new` creates directories even for empty categories, including DEBIAN, bin, usr/bin, usr/sbin, etc/<package>, usr/lib/systemd/system, etc/init.d, usr/share/doc/<package>, usr/share/man/man1, usr/share/<package>, usr/lib/<package>, usr/share/applications, and usr/share/icons.

The skeleton does not synthesize copyright/changelog contents, service-enablement hooks, or policy completeness. The Gemini reference was design input, not a verified Debian-policy specification. Current inspection is of staged packages; do not imply that archive or installed-package inspection was implemented.

## 5. Metadata, editing, and dependency origin

**TLDR:** `set` validates metadata edits; `edit` opens the file directly. A dependency version constraint does not select its repository.

Fields are case-insensitive. `name` aliases Package. User-defined fields and multiline descriptions are supported. `set` validates candidate control metadata before replacement. `get` prints the value for scripts.

`pkg edit [<package>]` selects the package if needed and opens its actual control file. Editor precedence is VISUAL, EDITOR, then editor. Whitespace-separated arguments are supported without shell evaluation; complex quoting requires a wrapper. A literal editor executable path with spaces is supported. Direct editor changes are not normalized or validated by `pkg edit`.

Dependency forms:

```bash
pkg add dependency gum 2.0.2 to pkg-cli
pkg add dependency gum '>= 2.0.2' to pkg-cli
pkg add dependency 'gum (>= 2.0.2)' to pkg-cli
pkg add dependency curl '= 8.0' to myapp
```

A bare secondary version means `>=`; quote other comparisons. Versions are validated. Matching a dependency by its bare name can find a constrained entry. Identical additions are idempotent, while different constraints are not silently merged. Use dependency `mv` to replace a relationship. Force replacement applies to files, not dependency semantics.

The maintainer specifically requires `Depends: gum (>= 2.0.2)`. Their identity is `axjab <axjab@github.com>`. Preserve current metadata when delivering source changes. An older assistant control included `gum, openssh-client`; do not treat that as the current user-approved dependency list.

When multiple APT repositories supply `gum`, Depends constrains package identity/version and does not encode Charmbracelet as the origin. APT source configuration and preferences/pinning govern selection. The supplied Charm source was `https://repo.charm.sh/apt/`, with its key under `/etc/apt/keyrings/charm.gpg` and a signed-by source. No repository-origin management feature was implemented in pkg. Verify current repository metadata and official instructions before producing a concrete pin or installer change.

## 6. Version source and build architecture

**TLDR:** `.pkg/packages/pkg-cli/DEBIAN/control` is authoritative. Each compiled executable carries a snapshot of it.

The duplicate `packaging/pkg-cli.control` caused repeated version mismatches. It was removed from the assistant workspace and superseded by the single-definition overlay. That overlay intentionally omitted the user's control file. If the obsolete directory remains in the maintainer's checkout, inspect references and remove the stale file/directory explicitly.

The compiler bundles runtime `lib/` plus the canonical control file into a self-extracting Bash executable. `pkg version` reads the bundled control snapshot, independent of the current working directory. It does not query the installed dpkg database or a nearby workspace's current metadata.

There are therefore four separately observable states: control metadata, compiled executable, staged package executable, and installed executable. To release a changed version, update each through edit, compile, add, build/push, and client installation.

The inspected `do/build-deb` wrapper compiles into a temporary directory, stages that executable with explicit `add -f executable ... to pkg-cli`, then invokes build. It accepts optional `-f`, retains other staged components, and defaults SOURCE_DATE_EPOCH to 0 for its build workflow. It is a convenience wrapper around the ordinary commands.

The assistant compiler supports `PKG_COMPILE_DIR`; the default there is `/exe`. The maintainer's final demo instead uses `do/compile` producing `./pkg`. Preserve their current choice. In the older snapshot, `PKG_COMPILE_DIR="$PWD" do/compile` explicitly produces the checkout executable. The README documents this override and explains that bare `do/compile` suffices when already configured that way.

## 7. Confirmed release workflow

**TLDR:** The maintainer published 0.2.2 and upgraded through APT. `apt update` refreshes availability; the subsequent upgrade replaces the installed command.

From the maintainer's checkout with package and publishing host already configured:

```bash
pkg edit                  # change Version to 0.2.2, save, exit
do/compile               # produces ./pkg in the maintainer's current setup
pkg add -f ./pkg           # replace staged bin/pkg
pkg build                 # dist/pkg-cli_0.2.2_all.deb
pkg push                  # select the new archive if prompted
sudo apt update
pkg version               # still 0.2.1 before installation
sudo apt upgrade
pkg version               # 0.2.2
```

For a targeted update, use `sudo apt install --only-upgrade pkg-cli` instead of upgrading all packages. For an absent package, use `sudo apt install pkg-cli`. The maintainer used `pkg build -f` during the successful 0.2.2 demonstration; plain build is sufficient when there is no conflicting archive.

The observed final installation fetched `pkg-cli_0.2.2_all.deb` from `https://apt.alj.cx`, unpacked it over 0.2.1, and completed setup. This is actual maintainer evidence, separate from assistant-side simulated publication tests.

### Earlier failure and diagnosis

The maintainer force-replaced an already published 0.2.0 archive. APT still expected 21,592 bytes, while the new archive contained 21,644 bytes. During this session the live Packages index was checked and already listed 21,644 bytes for 0.2.0. The local APT package list was stale. Refreshing it with `sudo apt update` was the appropriate next step; repeated install or `--fix-missing` did not refresh that index.

At the same time, `pkg version` printed 0.1.2 while `./pkg version` printed 0.2.0. This proved different executable content was running, but the exact PATH winner was not supplied. `/exe/pkg` shadowing the installed command was a hypothesis, not a confirmed diagnosis. Use `type -a pkg`, `command -v pkg`, and explicit paths when investigating. Building/publishing does not install the package or update other standalone copies.

## 8. Force behavior and publication guarantees

**TLDR:** `-f` is a leading optional flag for add, build, and push. Replacing a published version changes the bytes behind its existing URL.

| Invocation | Scope |
| --- | --- |
| `pkg add -f ./pkg` | Replace a conflicting staged regular file |
| `pkg build -f pkg-cli` | Replace a conflicting local archive after building and verifying a candidate |
| `pkg push -f pkg-cli to apt` | Replace a published archive of the same package/version/architecture and regenerate signed metadata |

Normal identical-content operations remain idempotent where supported. Normal conflicting content fails with guidance. Symlink/directory targets are rejected where regular files are required. Failed copying/build verification preserves existing content and cleans owned temporary files. Copy failures retain their underlying status and debug events.

Push selects an existing archive in dist; it does not build implicitly. Multiple versions prompt in a terminal and fail noninteractively. Inspect current behavior before assuming it automatically selects the highest version. A host is inferred only when unambiguous. Literal localhost uses local execution.

The inspected force publisher serializes checksum and force arguments through both local and SSH execution paths, locks publication, stages and verifies metadata/signatures, and exchanges prepared files/directories. A same-name archive replacement retains the old archive for rollback if suite activation fails. A commit marker distinguishes successful activation. Rollback failure preserves recovery material and emits guidance. GNU mv exchange support is required by this implementation; verify target compatibility before changing deployment assumptions.

This does not provide whole-repository atomicity to all readers. In particular, old client indexes and retained by-hash indexes can still reference the reused archive URL with old hashes after forced replacement. Prefer a new version for normal releases. Same-version replacement also does not become a higher version for ordinary APT upgrades; deliberate reinstallation may be needed after refreshing indexes.

## 9. Tests and outstanding limitations

**TLDR:** The newer Bash checks passed during implementation. The legacy suite remains unresolved and must be reported honestly.

`do/test-schema` anchors to the project root, compiles into a temporary directory, exports PKG_TEST_BINARY, and runs these Bash scripts:

- `test_pkg_actions.sh`
- `test_pkg_inspect.sh`
- `test_pkg_schema_terminal.sh`
- `test_pkg_usability.sh`

Those checks cover the action model, metadata, component operations, inspection, ambiguity, numbered prompts, dependency versions/grid, editor invocation, persistent choices, copy-failure handling, and package building. The last implementation checkpoint reported them passing. They were not rerun solely for this handoff edit.

Force publication checks included successful replacement, normal conflict rejection, injected suite-activation failure with rollback, and SSH argument serialization using stubs. Real GPG-agent startup was blocked in the assistant environment. These checks do not substitute for real SSH/GPG tests; the maintainer subsequently supplied successful live publication and APT upgrade evidence.

The older `do/test` remains a Python unittest entry point. Do not say the repeated failing-tests requests were fully resolved: they were not. Some actual regressions were repaired, but much of the old suite was not migrated.

| Failure group | Assessment / next action |
| --- | --- |
| Old create/help/output wording | Update expectations to the accepted schema |
| Bare filenames now ambiguous with dependencies | Use explicit file paths/categories for setup; retain ambiguity tests |
| Package menus fed names or Gum stubs | Migrate to numbered input; prevent PTY timeout loops |
| Exact diagnostic/status expectations | Review against intended contracts; preserve rejection and no-mutation assertions |
| Empty `to ""` accepted | Real regression repaired; verify retained coverage |
| Copy failure lost status, temp cleanup/debug events | Real regressions repaired; verify retained coverage |
| Enter without a remembered default | Changed to cancellation rather than an endless prompt |
| GPG fixture/agent errors | Separate environment constraints from publisher defects |

No universal policy linter, automatic Debian documentation generation, automatic service enablement, installed/archive inspector, general distribution support, or repository-origin dependency selector was completed. Directory addition is not recursive; stage individual files. Existing limitations should be addressed only when selected for work.

## 10. Source map

**TLDR:** Share parsing, classification, and metadata logic; avoid introducing parallel implementations.

| Paths | Responsibility |
| --- | --- |
| `.pkg/packages/pkg-cli/DEBIAN/control` | Single package definition and compile-time version source |
| `do/compile`, `do/build-deb` | Standalone compilation and self-package build wrapper |
| `do/test`, `do/test-schema` | Legacy and Bash test entry points |
| `lib/actions.sh`, `lib/categories.sh` | Component action resolution and taxonomy |
| `lib/choose.sh`, `lib/package.sh`, `lib/workspace.sh` | Selection, package/workspace discovery and validation |
| `lib/metadata.sh`, `lib/control.awk` | Metadata parsing and mutations |
| `lib/depends.sh`, `lib/depends.awk` | Dependency relationships |
| `lib/grid.sh`, `lib/inspect.sh`, `lib/list-components.sh` | Inspection and formatted/query output |
| `lib/pkg-*` | Individual command entry points |
| `lib/hosts.sh` | Host handling |
| `lib/push-{readiness,metadata,publish,output}.sh` | Publication stages, activation, diagnostics |
| `install.sh`, `do/update-install-script` | Repository bootstrap source and deployment helper |
| `README.md` | User reference, now starting with the release demonstration |

The shell bootstrap/deployment scripts may use POSIX sh; preserve their interpreter requirements. Keep runtime diagnostics on stderr and script-friendly values on stdout. Preserve quoted argument forwarding, caller-relative source paths, and private temporary staging.

## 11. Retained repository/bootstrap operations

**TLDR:** Signed hosting and bootstrap already work. Preserve the existing trust and serving boundaries.

The confirmed publishing alias is `apt`; the recorded remote account home/repository root is `/srv/pkg/apt`. The public endpoint is `https://apt.alj.cx`. Distribution/component/index architecture are trixie/main/amd64, including architecture-independent all packages.

Repository files include public `apt-signing-key.asc`, `dists/trixie/{InRelease,Release}`, `main/binary-amd64/{Packages,Packages.gz,by-hash/SHA256/...}`, and `pool/main/*.deb`. Existing unrelated packages must survive index regeneration. The observed signing fingerprint was `17807F5DED23C905CCD81EBD258FB9551F4E7C7B`; it is historical evidence, not a constant to hardcode. The bootstrap's pinned key-file SHA-256 is different from a GPG fingerprint.

Push provisions a signing key for a suitable new unsigned repository, using batch ed25519 signing with an empty passphrase and no expiration. Established signing keys must be preserved. Never rotate keys silently.

Client bootstrap:

```sh
curl -fsS https://apt.alj.cx/install | sh
sudo apt install pkg-cli
```

The bootstrap configures trust/source and refreshes APT. It has no package profiles and does not choose packages to install. Its existing contract uses a normal user with sudo and requires configured publisher URL/key digest values. Preserve the configured script rather than restoring an unconfigured template.

Caddy's recorded serving boundary exposes repository metadata, package pool, public key, and bootstrap, with a minimal navigation page. The separately deployed bootstrap is `/srv/pkg/bootstrap/install.sh`. Do not broaden serving to the account home, GPG state, SSH state, or staging/backup directories. Inspect live configuration before altering routes; `/install` is the confirmed URL.

The source inspected at session close confirms `do/update-install-script` reads root `install.sh`, runs `sh -n`, uploads one file with rsync checksum comparison and mode 0644, fetches the HTTPS URL, and compares bytes before success. Defaults are INSTALL_HOST=old_shrine, INSTALL_PATH=/srv/pkg/bootstrap/install.sh, INSTALL_URL=https://apt.alj.cx/install. Its execution was not verified in this session. `dist/install.sh` is a copy, not another authoritative source. No continuous synchronization was established.

Earlier confirmed disposable-container testing installed helloworld 0.0.0 through the bootstrap and executed tty-notify successfully. Dockerfile/do/start-os provide the development test container; inspect current paths and tags before use. A future clean CLI installation test should let APT resolve Gum to avoid masking missing dependency repository setup.

## 12. Recovery artifacts and final state

**TLDR:** Use the current checkout first. The delivered overlays are incremental and some contain superseded metadata layouts.

Recent recovery artifacts, in development order:

- `pkg-gum-selection.zip`
- `pkg-cli-packaging.zip` — historical packaging layout/version
- `pkg-package-contents.zip`
- `pkg-inspector-skeleton.zip`
- `pkg-inspector-display-fix.zip`
- `pkg-action-schema.zip`
- `pkg-usability-update.zip`
- `pkg-build-force-and-version.zip`
- `pkg-cli-final-overlay.zip` — predates later force and single-definition corrections despite its name
- `pkg-0.1.1-force-add-push.zip` — force features, but superseded metadata source
- `pkg-single-package-definition.zip` — removes reliance on packaging/pkg-cli.control; contains compile/build wrapper/version/test/README changes, intentionally excludes user control

[Single-definition recovery overlay](https://chatgpt.com/library?file_id=libfile_2ff71cc6aad88191b6f7f772a9527d8f&account_id=personal)

[Force add/push recovery overlay](https://chatgpt.com/library?file_id=libfile_9075382cf4d08191a914457b48437c0f&account_id=personal)

[Updated README](https://chatgpt.com/library?file_id=libfile_3e74462e56848191913c2fc3161e89a2&account_id=personal)

The delivered 0.1.2 Debian archive predates the final single-definition correction. Do not distribute it as the current release. The maintainer built and published 0.2.2 themselves; no assistant-built 0.2.2 archive is claimed.

Session closes with the 0.2.2 production upgrade confirmed, the README release walkthrough delivered, and this handoff updated. Remaining work starts with the current checkout and honest test-suite reconciliation. No issue posting, production changes, or new implementation work was performed as part of this documentation wrap-up.
