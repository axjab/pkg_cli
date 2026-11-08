# pkg_cli — authoritative development handoff

Updated 2026-11-08. Read this before changing code. This document reconciles the original prompt, README, STATUS, TODO, roadmap, subsequent decisions, and the maintainer's latest instruction.

## TLDR for the maintainer

Local init/create/add/build and host registration/ping are implemented. Proceed directly with **iterative implementation of `pkg push`**, including preflight checks inside that command. Deliver a ZIP of replacement source files for each checkpoint; the maintainer extracts it, runs `bash compile`, tests `pkg`, and returns output. Fix that checkpoint before advancing.

The remote SSH account's home is the APT repository root. HTTPS is outside scope. The standalone-first requirement is explicitly superseded. Do not ask permission to begin work already requested.

## 1. First action for the next agent

Inspect the available current implementation and tests, then implement the first useful `pkg push` checkpoint. Do not begin with another planning interview, a standalone preflight deliverable, documentation cleanup, or a new naming discussion.

Start with selection of one built package and an SSH host, followed by integrated remote readiness checks. Reuse the workspace, package, host-selection, and debug helpers. Use the existing `publish-preflight` prototype as reference, adapting it to the established helpers and output style. Package all runtime dependencies under `lib/` so the compiled executable works away from the checkout.

Make the first increment callable through `pkg push` and `pkg help push`. If it only checks readiness, say so and explicitly say no package was published. Never print publication success for a partial implementation. Report the limited checkpoint to the maintainer and supply precise test commands and expected outcomes. Do not stop at a design proposal.

If the current source is unavailable, first retrieve the linked implementation snapshot below. Ask for specific missing source only when it truly blocks implementation; do not require the entire checkout merely to avoid inspecting the available snapshot. State which source baseline was used.

## 2. How we work together — essential contract

The maintainer designs the product and runs real-environment tests. The agent implements, tests in its own environment, and supplies files. This is an ongoing collaboration, not a generic advisory session.

- Work in small, concrete increments. Each increment should exercise the normal CLI entry point and be useful to test immediately.
- Make routine engineering choices using expertise. The maintainer explicitly authorized intuition and optional arguments. Ask a focused question only for a consequential unresolved product decision that cannot be inferred from accepted behavior.
- Distinguish uncertainty in the CLI from uncertainty in the conversation: interactive CLI selection is wanted; repeated planning questions are not.
- Explain behavior in plain English, then show the corresponding command. Label a genuinely new interface proposal as proposed. Do not reopen settled decisions.
- Test your change before delivering it. Then stop at the maintainer's manual verification gate. Do not silently advance through several checkpoints in one release.
- When the maintainer supplies an error, investigate and repair the current checkpoint. Preserve accepted behavior. Roll back and redesign a misdesigned step when necessary.
- Keep replies short, concrete, and actionable. State what changed, what tests actually ran, any remaining limitation, and the exact commands to try.
- Do not claim a real SSH, APT, or installation test passed when only mocks or local fixtures ran.
- Notify the maintainer when the session becomes long enough that a handoff would prevent context loss. Do not imply background chat monitoring exists.
- Docs and unrelated cleanup remain deferred during implementation. This requested reconciliation is an explicit documentation task, not authorization for broad cleanup later.

### The delivery loop — ZIP, compile, test, feedback

For every implementation checkpoint:

1. Inspect the actual source baseline. Change only what is necessary for that checkpoint.
2. Test the Bash handlers and the compiled CLI as appropriate.
3. Produce a downloadable ZIP containing complete replacement/new files at checkout-relative paths. Expected top-level entries are `lib/` and `tests/`, plus `compile` only if it actually changed. Do not introduce an enclosing directory that causes extraction into the wrong place.
4. Include all newly needed runtime helpers. Preserve executable modes on handlers. Check the ZIP's paths, contents, and permissions before delivery.
5. Omit package data, credentials, caches, generated archives, virtual environments, and unrelated files. Do not ship a stale whole checkout that overwrites newer unrelated work.
6. Name the replacement files in the short delivery message. The ZIP is an overlay: extraction overwrites those files while leaving unrelated files alone. If a removal is truly required, state it explicitly; a ZIP cannot remove old files by omission.
7. Give the maintainer a short test sequence: extract over the checkout, run `bash compile` there, change to the package workspace, and invoke installed `pkg`.
8. Wait for the maintainer's output or approval before the next checkpoint.

The maintainer should not need to hand-edit snippets, run a separate standalone publication toolkit, or learn your test harness. Provide a real downloadable artifact, not merely a filename. Keep ZIP contents cumulative enough to include dependencies required for the delivered change. Do not alter `/exe/pkg` or the maintainer's production repository remotely unless that execution is specifically part of the requested work.

## 3. Authority and resolved decisions

Priority: latest maintainer instruction → actual current source for existing behavior → this reconciled contract → older documents as historical reference. Source describes what exists; the latest instruction defines the change to make.

| Topic | Settled direction |
|---|---|
| Command/repository | `pkg`, exactly three characters; repository `pkg_cli`. No naming review. |
| Workspace | One `.pkg/` marker per workspace containing several packages. |
| Package storage | `.pkg/packages/<name>/`; managed metadata and internal state under `.pkg/`. |
| Build | Local by default. `pkg push` publishes a previously built local archive. |
| Discovery | Git-inspired nearest-workspace discovery; no fallback to a remembered unrelated workspace. |
| Remote syntax | SSH aliases or `user@host`; honor normal SSH configuration. |
| Destination | Target SSH account's home directory is the APT repository root. |
| HTTP/HTTPS | Maintainer manages it separately. No web-server provisioning work. |
| Preflight | Integrated into `pkg push`; reusable internal helpers are fine. |
| Development gate | Test and deliver each ZIP; maintainer recompiles and verifies. |
| Long-term SSH | Important architectural direction; do not make build remote by default. |

### Explicitly superseded instructions

- “Do not implement pkg push until all standalone scripts are finished” is revoked by the latest request. Implement push now, iteratively.
- “Next: agree on package selection / implement add / build” is stale. Those steps are implemented.
- “Next: discuss a standalone preflight” is stale. Integrate the existing work into push.
- `~/public/apt` and `publish:public/apt` describe an older server. Do not use them for the new target or ask again where the repository lives.
- Do not ask for a positional workspace or repository-directory argument for routine publication. Discover the local workspace and use the target home remotely.
- The old roadmap's open command-name, marker-name, and one-package-per-workspace questions are resolved.
- Old `pkg-init <package>` and checkout-relative `deb/` workflow are legacy references, not current syntax.
- Old plans for standalone remote configuration are superseded by implemented `pkg host`/`pkg hosts` and `pkg ping`.

## 4. Current CLI and implementation baseline

### Bundling and dispatch

`compile` takes no arguments, bundles the current directory's entire `lib/`, and writes `/exe/pkg` with mode `0755`. The hardcoded destination is deliberate. Invoke `bash compile` from the checkout root.

The bundled Bash launcher extracts handlers to temporary storage and dispatches `lib/pkg-<command>`. Helpers are sourced relative to each handler, not relative to the caller's workspace. Forward arguments with `"$@"` and preserve the caller's working directory and meaningful status codes. Runtime code must not depend on checkout-only `tools/` or `_tmp/` paths.

Use `pkg help` and `pkg help <command>`. The dispatcher routes command help to the handler's `help` operand. The supported global flag is `pkg --debug <command>`. Avoid new double-dash arguments.

### Workspace and package operations

- `pkg init` initializes the current directory if no ancestor workspace exists, or preserves/reuses the nearest existing workspace. It does not implicitly create a package or run `git init`.
- `pkg ls` prints sorted package names, one per line. Empty workspace: empty stdout. Discovery failure: status 1.
- Discovery starts in the current directory and searches physical parents. A malformed marker stops discovery. Current marker/storage symlink restrictions must be preserved; inspect the resolver before changing them.
- `pkg create <name>` makes an empty package and rejects duplicates without data loss. Control defaults: version `0.0.0`, architecture `all`, section `utils`, priority `optional`; maintainer and description are placeholders.
- `pkg add <executable> [to <package>]` stages one executable into the package's `bin/`. The short form `pkg add <executable> <package>` is also implemented. Source paths are caller-relative. Identical existing content is accepted; different existing content is preserved and rejected.
- `pkg build [<package>] [to <directory>]` builds and checks an archive. Default destination is workspace `dist/`; explicit relative output is caller-relative. It prints the absolute archive path to stdout. Existing conflicting archives are preserved. Output inside `.pkg/` is rejected.
- Omitted package selection uses the sole package or prompts in a terminal when several exist. Noninteractive ambiguity fails with explicit-selection guidance. An unknown package should point to `pkg create <name>`.

Shared code includes `workspace.sh`, `package.sh`, and `hosts.sh`. Inspect and reuse their actual interfaces rather than inventing names or duplicating logic.

### Host commands — approved checkpoint

```bash
pkg host add pkg-host
pkg host
pkg hosts
pkg ping pkg-host
pkg ping
```

Registration is offline and workspace-local in `.pkg/hosts`. Both listing commands work. With no registered hosts, print guidance to stderr, keep stdout empty, and exit 0:

```text
No hosts configured. Add one with pkg host add <host>.
```

Explicit `pkg ping <host>` works outside a workspace. Omitted target selects the sole registered host or prompts for ambiguity. SSH failures preserve SSH status, including 255. Literal `localhost` uses direct local execution. Do not silently treat all host aliases or `user@localhost` as the current local identity; preserve existing transport semantics unless deliberately extending them.

Checks are green on success and red on failure. Redirected check output is plain; honor `NO_COLOR=1`.

Target configuration:

```sshconfig
Host pkg-host
    HostName old_shrine
    User apt
```

Accept both `pkg-host` and `apt@old_shrine`; delegate alias resolution to SSH. The dedicated host may not be ready. A clear expected connection failure is a valid first manual checkpoint; do not fake success or attempt to provision it.

## 5. Publication behavior and scope

### Operator goal

The operator builds locally, chooses a host, and pushes. pkg generates repository boilerplate. Once the repository source and public key are configured on a fresh Debian system, the package must be discoverable and installable by name.

Interface direction:

```bash
pkg push [package arguments...] [to <SSH target>]
```

Begin with one package. Support explicit and omitted selectors using existing conventions. If exactly one package/host is available, infer it. For ambiguity, prompt in a terminal and require explicit selection in scripts. Do not invent batch/all selection semantics merely because the long-term notation allows several arguments.

Use built artifacts from the selected workspace. Do not implicitly build, upload every `dist/*.deb`, choose a random version, or select by mtime without an explicit contract. Derive package identity from archive/control metadata as needed. For the initial implementation, use the existing build naming convention and default artifact location; missing output must suggest building first. If more than one artifact fits, resolve it clearly rather than guessing. Custom build-output selection can be extended later without blocking the basic path.

### Target layout

The following paths are relative to the **target account's home**, not an additional `apt/` subdirectory:

- `apt-signing-key.asc`
- `pool/main/<package>_<version>_<architecture>.deb`
- `dists/trixie/main/binary-amd64/Packages`
- `dists/trixie/main/binary-amd64/Packages.gz`
- `dists/trixie/Release`
- `dists/trixie/InRelease`

Use `trixie`, `main`, and the initial amd64 client index as the established starting target. Include architecture-independent (`all`) packages in the index consumed by amd64 clients. Preserve unrelated repository packages when generating indexes. No requirement for generalized distributions, components, or architectures in the first checkpoint.

Do not touch HTTPS configuration. Do not upload a private signing key or expose secrets in output. The public key must correspond to the actual signature used by clients. Key provisioning, rotation, and unlocking policy should not become an unsolicited infrastructure project.

### Existing preflight prototype — reference, not a new operator prerequisite

The current `publish-preflight` artifact was read during this reconciliation. It:

- Accepts one SSH target, with terminal prompting if omitted; uses direct execution for literal `localhost`.
- Runs remote Bash over SSH with batch mode, bounded connection attempts, and no forwarding.
- Uses target `$HOME` as repository root and verifies it is an accessible absolute directory.
- Checks target tools including GPG, apt-ftparchive, gzip, rsync, awk, mktemp, mv, and rm.
- Creates a temporary directory beneath the target home; tests write, rename, and removal; cleans up probes.
- Requires an existing GPG keyring. It does not provision keys or repository metadata.
- If `apt-signing-key.asc` exists, uses its primary fingerprint to select and verify signing. If signed repository metadata exists without that public key, fails.
- For a new unsigned repository without the public key, requires exactly one suitable secret signing key.
- Signs a temporary payload in batch/no-TTY mode with pinentry disabled and verifies using only the corresponding public key.
- Removes temporary probes and reports the selected root and fingerprint.

Port useful checks into `pkg push` or a sourced helper under `lib/`. The prototype is not evidence of a successful real-host test. Improve its selection/errors/colors/debug integration to match pkg; do not blindly copy a second CLI interface. Run checks for the operations actually used; avoid unrelated prerequisite inventories. A cached signing passphrase can make a test pass without proving unattended signing after reboot.

## 6. Iterative implementation plan inside pkg push

These are increments of one public command, not a required set of standalone commands. Adjust the smallest useful boundary to the inspected code, without restarting design.

1. **Selection and integrated readiness:** route through `pkg push`, resolve workspace/package/archive/host, check local input and remote prerequisites/permissions/signing. Test successful local fixtures and SSH failure. Deliver ZIP. Explicitly report readiness only.
2. **Transfer and integrity:** transfer only the selected archive to temporary target storage, compare checksum, and clean up failures. Do not expose an incomplete archive as published. Deliver and verify.
3. **Repository metadata:** generate Packages, Packages.gz, and Release in staging from the intended repository contents. Confirm relative filenames and hashes, preserve other packages, and index `all` correctly. Deliver and verify.
4. **Signing and activation:** produce and verify InRelease against the intended public key, export the public key when appropriate, and make the prepared publication usable. Preserve the previous usable repository on failed preparation; stage multi-file changes before activation. Keep the design simple, but do not claim whole-repository atomicity without testing it.
5. **End-to-end verification:** clean Debian source/key configuration, apt update, package discovery, install and executable check; then upgrade, retry, conflicting-version behavior, and interrupted publication checks as appropriate.

For retries, prefer accepting an already present identical archive and rejecting different bytes for the same package/version/architecture. This follows existing add/build preservation behavior. Confirm any meaningful new overwrite policy before implementing it. Avoid a sophisticated transaction framework as a prerequisite to the first readiness checkpoint; resolve activation/concurrency details when that stage is implemented.

## 7. Code, diagnostics, and testing requirements

### Bash and data preservation

Use `#!/usr/bin/env bash`, `set -euo pipefail`, descriptive variables, readable validation, and brief intent comments. Quote paths and expansions, support spaces, and forward arguments with `"$@"`. Handle SSH/rsync remote quoting deliberately; never concatenate unchecked operands into shell code. Preserve statuses through pipelines and cleanup traps.

Keep abstractions small. Separate transport where useful so localhost and SSH share operation logic. Avoid generic remote-execution frameworks or speculative configuration. Keep operator-facing access to managed state in the CLI; do not require manual editing of `.pkg/` as the normal workflow.

Preserve data on failures and duplicates. Stage multi-file work, clean only owned temporary state, and test concurrent duplicate attempts where relevant. Never use destructive synchronization against the target home. In particular, SSH and GPG state may also live there; publication must not remove unrelated home contents.

### Debug and output

Diagnostics go to stderr; keep stdout useful to scripts. Reuse existing debug helpers and stable field ordering. Emit context before an operation and outcomes as known:

- Current-directory marker presence, each searched path, discovery result, selected workspace.
- Selected package/artifact, host, resolved remote root, and actual operation targets.
- Relevant transfer, verification, signing, and publication outcomes.

Log runtime values from the performing code, not guessed descriptions. Cyan labels, green true/success, red false/failure; honor `NO_COLOR=1` and established redirected-output behavior. No locale dumps or unrelated environment information. No secret material.

### Tests and honest evidence

Use Python standard-library unittest invoking Bash, consistent with existing tests. Cover meaningful success and failure, not just mirrored implementation details.

```bash
python3 -m unittest discover -s tests -v
```

Also test the compiled command through normal dispatch: `pkg help push`, selection/discovery, stdout/stderr, exit status, debug/color behavior, paths with spaces, and failure cleanup. Use disposable workspaces and a disposable target home/keyring. Do not alter the real HOME variable for unrelated tasks; isolate fixtures deliberately.

Previous compiled tests used a temporary bind mount as `/exe` and `PKG_TEST_BINARY`. Reuse the existing test conventions when available. Do not change compile's hardcoded destination merely to simplify tests. If tooling prevents a compiled test, disclose exactly what was and was not tested.

For the first push checkpoint cover explicit selectors, sole-choice inference, interactive versus noninteractive ambiguity, missing archive, SSH failure/status, localhost readiness, missing tool, unwritable destination, absent/ambiguous key, signing failure, and successful verification as relevant. Expand transfer/index/activation tests with their respective checkpoints.

## 8. Evidence and limitations — do not confuse history with current verification

- The accepted host checkpoint previously reported 45 passing tests, including handlers and bundled entry-point checks. That is historical evidence, not a new run for this handoff or a future modified ZIP.
- Previous local builds were manually installed in Debian 13. Old manual SSH publication generated signed metadata; a later session record reported successful installation after configuring the APT source.
- The attached older STATUS still says end-to-end installation was unverified because the source was missing. Treat it as stale historical status; neither old outcome verifies the new host or new `pkg push` implementation.
- Standalone preflight source exists and was inspected. Its live-host verification is not established here.
- Do not infer the dedicated host is reachable or signing-ready. The maintainer originally wanted to see a real failure before creating/configuring it.
- This handoff updates documentation only; it does not deliver a new implementation or claim push works.

## 9. Deferred work and issue status

- `pkg -C <directory>`: deferred. Do not implement it as a prerequisite for push. Relative path semantics for that future option remain separate.
- Standalone `.deb` validator: deferred. Draft issue title is “Add a standalone .deb publication validator.” Basic checks required by push still belong in push; do not revive a separate command as a gate.
- No GitHub issue was actually posted during the earlier issue-drafting step: no token/issue connection was available. Do not report drafts as filed issues.
- Use direct curl to GitHub's API, never `gh`. Latest issue-script target was `axjab/pkg_cli`; `axjab/packages` appeared earlier. Verify the destination if posting later.
- Legacy `deb/` migration, remembered local project registries, remote workspace operations, general remote builds, installers, other package collections, and cleanup are later work.
- Future bootstrap should configure the source/key so a fresh Debian client can install by name; HTTPS provisioning remains outside pkg publication scope.

## 10. Sources and recovery

The five attached documents were read and reconciled: the original workspace-step README, old STATUS, planning roadmap, standalone-pipeline TODO, and prior handoff. Their obsolete instructions are replaced by this contract. Keep them as references, not competing active plans.

Implementation snapshot (host checkpoint):
[pkg-publish-ssh-step.zip](https://chatgpt.com/library?file_id=libfile_678828fec7c08191921a9627c3250c01&account_id=personal)

Current standalone reference to incorporate:
[publish-preflight](https://chatgpt.com/library?file_id=libfile_946ed0a3fc4c81918930e6ad1733afc6&account_id=personal)

Interactive direct-API issue script:
[github-issue.sh](https://chatgpt.com/library?file_id=libfile_c544eac4a1dc81919c46a55cab9d5912&account_id=personal)

A scratch snapshot existed at `/workspace/scratch/e10931fce349/pkg_cli` during this reconciliation. Its add/build/compile sources were inspected to check syntax. It is not a mounted live maintainer checkout and may not survive into the next session. Never claim to have changed the maintainer's checkout when you only prepared an overlay ZIP.

When resuming: load available source, implement the first integrated push increment, test it, deliver the replacement ZIP and a short manual test. The maintainer recompiles and tests. Continue from their results.
