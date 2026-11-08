# Installation Script Engineering Blueprint

**Status:** reference-grounded engineering specification · **Scope:** Linux first, Debian/Ubuntu/APT priority · **Audience:** AI coding agents and Linux engineers · **Evidence baseline:** nine user-supplied references, inspected statically on 2026-11-03.

> **Implementation contract.** An installer conforming to this document has a declared support matrix, trust model, privilege model, mutation policy, recoverability limits, and testable acceptance conditions. It does **not** claim universal compatibility or transactional behavior for an entire operating system.

## 1. Purpose, scope, and assumptions

This document defines how to design **new** installation scripts; it is not an installer. The reference code was treated as untrusted **data** and was **not executed**. Findings marked **Observed** come from the supplied files; **Inferred** explains plausible consequences; **Recommended** is independent engineering judgment; **Conditional** requires stated circumstances; **Rejected** denotes a method not to copy without an exception. Line references are one-based lines in the supplied files, not upstream commits.

Supported installer families: (A) standalone executable, (B) archive-based, (C) APT bootstrap, (D) user-local development tools, (E) systemd service, and (F) a hybrid. Supported platforms must be specified **per project**. This standard does not imply that a given release exists for every architecture, ABI, Linux distribution, or release. macOS/Windows-specific reference features inform comparison only.

**Project-specific inputs that an agent must obtain or substantiate:** product name, artifact naming scheme and authoritative download origin, supported distribution/releases and CPU/ABI tuples, version selection policy, immutable trusted checksum/signature or APT signing-key identity, installation scope and destinations, ownership of existing files, PATH and service policy, configuration migration policy, minimum external tools, and success criteria. **Never invent any of these.**

## 2. Engineering principles and default decisions

1. **Safety before modification.** Separate detection and planning from network operations and privileged writes. Abort unsupported or ambiguous installations before mutation (`REQ-001`).
2. **Smallest sound implementation.** Choose `#!/bin/sh` with POSIX features by default; select Bash if arrays, expressive traps, or other capabilities materially reduce risk. Declare interpreter/version (`DEC-001`, `REQ-002`).
3. **Authenticate before execution.** TLS validates the connection; a checksum detects a mismatch with its supplied digest; a trusted signature or independently pinned digest authenticates a particular artifact. These are not interchangeable (`REQ-003`).
4. **Least privilege.** Download, parse metadata, and verify as an ordinary user; elevate only narrowly scoped system mutations. Never pipe untrusted network data into a privileged shell (`REQ-004`).
5. **Converge on target state.** Repeated execution must neither duplicate APT sources/PATH entries nor erase unrelated configuration. Make no-op, upgrade, downgrade and conflict behaviors explicit (`REQ-005`).
6. **Failure-aware transitions.** Stage artifacts; commit by a same-filesystem rename when feasible; distinguish rollback-capable local file changes from unrollbackable package-manager and service operations (`REQ-006`).
7. **No masked errors.** Check critical commands explicitly; `set -e` is supplementary, not an error model. Prefer informative failures to best-effort insecure success (`REQ-007`).
8. **Finite recovery.** Retry only transient network failures, with bounds; never retry mismatched hashes, bad signatures, unsupported platforms, or permission denials indiscriminately (`REQ-008`).
9. **Usability with consent.** Default non-interactive paths and service actions must be specified. Do not edit shell profiles or start services silently (`REQ-009`).
10. **Verify outcomes.** A successful download, `apt-get install` exit, or `mv` alone does not establish the required executable/service state (`REQ-010`).

### Non-negotiable constraints

`REQ-011` Keep TLS and APT signature verification enabled. `REQ-012` Reject missing required integrity tools; never silently skip checks. `REQ-013` Do not replace existing unmanaged configuration without a documented migration/consent path. `REQ-014` Prevent symlink/path traversal and unsafe archive extraction in privileged operations. `REQ-015` Do not print credentials or tokens in verbose logs. `REQ-016` No automatic root invocation solely to make a download work. `REQ-017` No success report before independent post-install verification. `REQ-018` Declare whether `curl | sh` is supported and its limitations.

## 3. Reference inventory and provenance

The references below are **snapshots supplied by the user**, not independently verified upstream revisions. **Analyzed** means static code review, not runtime validation. Docker and Mullvad are **instruction fragments**, not complete installers.

| ID | Project · supplied file | Interpreter / model | Intended platforms, privileges | Status and notable boundaries |
|---|---|---|---|---|
| `REF-01` | Tailscale · `tailscale.sh` (740 lines) | `sh`; distribution/package-manager dispatcher | Many Linux families; root via existing UID, `sudo`, or `doas`; also FreeBSD/macOS paths | Analyzed; remote repository content, package maintainer scripts and service outcomes not supplied |
| `REF-02` | rustup · `rust.sh` (930 lines; displays rustup-init 1.29.3) | `sh` plus common `local` extension; bootstrap to native executable | Unix families and Windows POSIX shells; initially user-level | Analyzed; actual `rustup-init` binary and downstream mutations unavailable |
| `REF-03` | Starship · `startship.sh` (554 lines; filename as supplied) | `sh`; direct release/archive install | Linux, musl, macOS, FreeBSD, Windows POSIX; escalates for bin dir | Analyzed; release artifacts, installed binary and digest not supplied |
| `REF-04` | dtop · `dtop-install-script.sh` (1,573 lines; embedded version 0.10.5, cargo-dist 0.31.0) | `sh` with non-POSIX `local`; archive + PATH + receipt | Linux/macOS architectures with embedded release mapping; user-local | Analyzed; generated artifacts and updater not supplied; source includes dormant/generalized code |
| `REF-05` | chroncal · `chroncal-install-script.sh` (163 lines) | `sh`; GitHub release archive | Linux, Darwin, FreeBSD, OpenBSD; local/system install | Analyzed; release manifest and archive contents not supplied |
| `REF-06` | Dux · `dux.sh` (97 lines) | Bash; binary bootstrap to secondary installer | Linux amd64/arm64, rejects root | Analyzed; **second-stage installer** absent; full installation unknown |
| `REF-07` | Ghostty Ubuntu build · `ghostty.sh` (137 lines) | Bash; distro mapping, download `.deb`, local APT install | Named Debian/Ubuntu/derivative versions, `sudo` when needed | Analyzed; remote release metadata and actual `.deb` absent |
| `REF-08` | Docker · `docker-apt-repo.md` (22 lines) | Markdown command fragment; deb822 source | Debian APT; root via `sudo` | **Partial**: key/source configuration only; no install/upgrade/error/cleanup logic |
| `REF-09` | Mullvad · `mullvad.sh` (9 lines) | Shell command fragment; one-line APT source | APT Linux; root via `sudo` | **Partial**: key/source/update/install snippets; no checks, matching, repair or service logic |

Evidence scope: no release repository was cloned, no secondary binaries were downloaded, no installer ran against the host, and no end-to-end behavior was tested. If current upstream scripts differ, this assessment describes only the supplied snapshots.

## 4. Individual reference-script analysis

### `REF-01` — Tailscale: package-manager dispatcher

**Architecture and flow (Observed).** `#!/bin/sh`, `set -eu`, definitions enclosed in `main()`, and a final `main` invocation (`tailscale.sh:L1-L22,L738-L740`). Validates `TRACK`, accepts optional `TAILSCALE_VERSION` (L35-L46); reads `/etc/os-release` and maps IDs, derivatives, releases and package managers (L48-L362). Falls back to `uname` for unidentified hosts (L365-L395). Chooses curl/wget, performs connectivity probe (L397-L420), checks a vendor support endpoint or a local distro policy (L422-L508), selects root/`sudo`/`doas` (L510-L529), then dispatches APT/yum/dnf/tdnf/zypper/pacman/pkg/apk/xbps/emerge/app-store commands (L532-L729). Prints `tailscale up` guidance (L731-L737).

**Strong/unique patterns (Observed).** Main-at-end reduces the likelihood that a truncated `curl | sh` stream executes early (L19-L22); derivative-aware mapping includes PikaOS and Linux Mint (L97-L114,L197-L210); explicit unsupported-platform diagnostics include detection output (L473-L507); separates platform policy from package manager implementation; tolerates an existing root session and `doas`; optional package version pin. Package-manager-specific DNF3/DNF5 handling (L589-L630) is a valid specialized compatibility technique.

**Weaknesses / inferred consequences.** Key and source downloads are piped to privileged commands (`$CURL ... | $SUDO tee`, L553-L562); POSIX `sh` offers no portable `pipefail`, so producer failure may not stop a successful `tee`, leaving empty/incomplete trust files. The legacy APT branch uses global `apt-key` (L553-L556), inappropriate for a modern Debian/Ubuntu-first design. Downloaded source definitions are trusted without local content validation; the remote `installer-supported` probe is not a cryptographic integrity check. `set -x` may disclose sensitive command arguments in general (L550-L575). APT index refresh and service enablement are unconditional on their respective branches (L565,L571-L574); no rollback or explicit already-current check. Not every manager includes health verification.

**Assessment.** **Adopt** explicit OS/package detection, constrained dispatch, fail-with-context, and main-at-end. **Replace** pipelines into privileged files with fully checked download-to-stage then verified atomic deployment. **Do not reproduce** legacy apt-key or distro-specific complexity unless genuinely required. **Limits:** upstream repo definitions, package scripts, and daemon health not examined. `REF-01 → PAT-ENV-001,PAT-APT-001,PAT-PRIV-001,PAT-BOOT-001`.

### `REF-02` — rustup: defensive second-stage bootstrap

**Architecture and flow (Observed).** `#!/bin/sh` with common `local` extension and compatibility alias (L1-L20), `set -u` (L26). `main()` validates downloader/dependencies, detects a fine-grained host target, chooses pinned/default rustup distribution URL, creates temp directory, downloads a native `rustup-init`, checks executability, handles piped-stdin TTY prompts, invokes second-stage with forwarded arguments, and cleans up (L70-L213). Host triple detection distinguishes ABI/userland bitness, ARM facilities, musl/gnu, x32, and architecture quirks (L216-L600). Downloader distinguishes curl/wget, snap-curl issues, TLS feature support, retries, and 404 diagnostics (L662-L919). Entrypoint also has a diagnostic architecture-print mode (L921-L930).

**Strong/unique patterns (Observed).** Real binary compatibility is more than `uname -m`: ELF bitness (L235-L254), userland mismatch (L545-L583), ARM capabilities (L585-L593). Explicit transfer error handling and compatible downloader detection; commands checked before use; prompts redirected to `/dev/tty` when script stdin is an installer stream (L193-L205); no fabricated pseudo-interaction. Failed download exits before execution.

**Weaknesses / inferred consequences.** This is a **bootstrap**, not the installer implementation: signature/checksum verification of the downloaded executable is not visible in the supplied shell (L171-L205). It relies on TLS and its distribution origin for bootstrap trust. Error handling deliberately uses explicit checks rather than `set -e`; some `local` declarations are non-POSIX and rely on common shells. TLS option probing and cipher-list code have significant maintenance burden and compatibility fallbacks (L697-L919). Cleanup is explicit rather than a signal/exit trap; abnormal termination can leave the temp directory. Actual `rustup-init` transactional/configuration behavior is unknown.

**Assessment.** **Adopt** dependent-native-binary compatibility checks only when artifact ABI truly requires them, TTY policy for piped execution, and dependency gating. **Conditional:** two-stage installers where a small shell launcher is justified. **Add** pinned/verified bootstrap authenticity where available, exit traps, bounded downloads. `REF-02 → PAT-ENV-002,PAT-BOOT-002,PAT-UX-001,PAT-DL-001`.

### `REF-03` — Starship: user-facing direct binary installer

**Architecture and flow (Observed).** `#!/usr/bin/env sh`, `set -eu`; log levels and `tput` colors (L1-L42), downloader supporting curl/wget/fetch (L44-L127), archive extraction by type (L130-L152), help/privilege handling (L155-L208), target mapping (`uname`, Linux-musl, word-size guard) (L217-L269), confirmation from `/dev/tty` (L271-L287), PATH/destination checks (L289-L313), shell-specific initialization instructions (L315-L388). Top-level option parsing (L416-L512), artifact target allowlist (L390-L414), release URL, prompt, install, and guidance (L514-L554).

**Strong/unique patterns (Observed).** Visible installation plan; explicit `--yes`, `--version`, target/path options; target allowlist before download; actionable manual shell setup rather than editing every startup file; recognizes `sudo` only when needed (L188-L208). Warns about PATH coverage and gives startup instructions. Linux-musl static artifact preference avoids common ABI issues where the build actually exists (L225-L227).

**Weaknesses / inferred consequences.** `get_tmpfile` creates a `mktemp` file then invents a **different** suffix path; if `mktemp` is unavailable it falls back to predictable `/tmp/starship.suffix` (L67-L75). Command execution via unquoted `$cmd` splits filenames/URLs (L99-L112); archive extraction into final destination happens before independent checksum/signature verification (L188-L208). `test_writable` creates predictable `test.txt` in destination (L79-L86), potentially clobbering an existing file. No cleanup trap. A `set -e` failure mid-extraction can leave partially replaced files; post-install reports success without checking executable operation. Target CLI argument parsing assumes operands exist for `--version`, etc. (L441-L462).

**Assessment.** **Adopt** clear plan and manual shell guidance, version selection, allowlist, optional confirmation. **Reject** predictable temporary fallback, direct extraction into bin, and executable installation without an artifact-trust rule. `REF-03 → PAT-UX-002,PAT-ENV-003,PAT-FS-001`.

### `REF-04` — dtop: generated archive installer, PATH and receipts

**Architecture and flow (Observed).** cargo-dist-generated `sh` script with common `local` extension; app/release constants, env overrides, receipt template and help (L1-L159). Entrypoint checks commands/options, detects target/ABI, selects a known release archive plus a **script-embedded SHA-256** per target (L161-L308), downloads from configured origins, checks hash, extracts, calls installer and writes a receipt (L310-L411). `check_glibc` rejects older GNU libc than release minimum (L496-L573). Installation supports custom `$HOME`/flat/cargo-home layout, stages binaries within the target filesystem, moves them to final paths, handles aliases, PATH, fish and shell RC files, CI PATH, and command shadowing (L575-L1025). Architecture detection includes OS/libc/ELF/CPU handling (L1027-L1384); helpers implement errors, command checks, download fallback and hashes (L1386-L1573).

**Strong/unique patterns (Observed).** Embedding exact hashes inside the already-obtained installer ties download bytes to this installer version (L233-L304); **staging in destination filesystem** before final rename reduces cross-device partial-copy risk (L728-L777); glibc minimum checks prevent obviously incompatible artifacts; command shadowing detection (L816-L829); optional no-PATH policy, XDG receipt placement and CI integration (`GITHUB_PATH`, L853-L867); mixed early/late-bound PATH expressions are explained in the source (L575-L614).

**Weaknesses / inferred consequences.** `verify_checksum` **returns success if hash tools are missing or hash style unknown** (L1496-L1563): incompatible with mandatory verification. `tar xf --no-same-owner --strip-components 1` (L375-L387) reduces some hazards but does not itself ensure safe archive members, symlinks, or expected structure. `_install_temp` is not protected by an exit trap, and renaming binaries one-by-one is not a multi-file transaction (L728-L777). Shell-profile editing covers many files and can be surprising; `ln -sf` aliases may overwrite conflicting user state without explicit checks (L767-L771). Receipt is produced using string substitution into JSON rather than robust JSON escaping (L719-L725); paths with special characters merit tests. `local` is non-POSIX; using `sh` as shebang relies on common shell implementations. Secondary updater behavior is not established from supplied artifacts.

**Assessment.** **Adopt** release-bound digest mapping, target-local staging, ABI constraints, optional PATH control, shadowing warnings, and receipts **where complexity is justified**. **Reject** silent verification downgrades, uncontrolled alias replacement, and unguarded profile edits. `REF-04 → PAT-SEC-001,PAT-FS-002,PAT-ENV-002,PAT-IDEM-002,PAT-UX-003`.

### `REF-05` — chroncal: compact standalone CLI installation

**Architecture and flow (Observed).** `sh`, `set -eu`; small helpers `have`, `download`, `latest_version`, OS/arch normalization, `checksum_file`, install path expansion and escalation (L1-L115). A `mktemp -d` workspace/trap (L117-L118), `VERSION` or GitHub API latest tag, artifact name construction, default install scope, archive/hash fetch, `tar` extraction, executable existence check, `install -m 0755`, PATH warning and best-effort version display (L120-L163).

**Strong/unique patterns (Observed).** Small purposeful functions; clear version/file naming; fallback downloader; matching checksum lookup (`checksums.txt`), refusal if the expected filename is missing (L72-L85); user-local fallback; executable presence check; predictable diagnostics.

**Weaknesses / inferred consequences.** `VERIFY_CHECKSUM=0` permits bypass; digest downloaded from **the same release origin** primarily guards corruption and mismatches, not independently authenticated publisher identity. Latest release is scraped from JSON with `sed` (L34-L38) rather than parsed structurally; `GITHUB_REPOSITORY` and `INSTALL_DIR` are unvalidated user input; `tar -xzf ... -C "$tmpdir"` extracts uninspected members and could write outside via archive paths/symlinks (L151). `mkdir -p ... || true` hides a relevant error (L101). `trap 'rm -rf "$tmpdir"' EXIT INT TERM` does not separately terminate on INT/TERM and may run cleanup more than once; `EXIT` acceptance is not identical on all POSIX-like shells. Final `version || true` means a broken executable can still be reported installed (L163). Existing target is replaced directly, not staged/atomically renamed.

**Assessment.** **Adopt** compact function decomposition and artifact filename/hash pairing. **Strengthen** auth policy, archive isolation, input validation, traps, conflict handling and final verify. `REF-05 → PAT-DL-001,PAT-SEC-002,PAT-PRIV-002,PAT-ERR-001`.

### `REF-06` — Dux: validated bootstrap to a separate installer

**Architecture and flow (Observed).** Bash, `set -e`; refuses root and non-Linux; maps x86_64/aarch64 (L1-L36). Resolves latest version via GitHub redirect header then JSON API fallback (L38-L54). `mktemp -d`, EXIT cleanup, legacy/new asset filename probe, downloads `.gz` and `.sha256`, compares SHA-256, gunzips/chmods and **executes** the downloaded second-stage installer with `"$@"` (L58-L97).

**Strong/unique patterns (Observed).** Explicit non-root boundary; architecture allowlist; avoids some GitHub API rate limits with redirect lookup; legacy asset fallback; checksum mismatch aborts before execution; forwarded user arguments; small single-purpose bootstrap.

**Weaknesses / inferred consequences.** The digest is retrieved alongside the executable from the same release location, not independently authenticated; thus hash comparison does not establish strong publisher identity on its own. `curl -sI` latest-version parsing is brittle under redirects/proxies; initial command failures may be masked by pipeline parsing and fallback. No strong final-state assertion because all installation work is delegated. Temporary directory cleanup uses trap, but no special signal handler. No explicit timeout/retry. The downloaded **second stage is unavailable**; never infer its idempotency, service effects, or file locations.

**Assessment.** **Conditional** for intentionally thin signed/pinned second-stage launchers. **Adopt** version lookup fallback and refusal to run as root when appropriate; **require** stronger immutable trust binding for executing downloaded bytes. `REF-06 → PAT-BOOT-002,PAT-SEC-002,PAT-DL-002`.

### `REF-07` — Ghostty: derivative-aware local `.deb` installer

**Architecture and flow (Observed).** Bash, `set -e`; sources `/etc/os-release`, queries `dpkg --print-architecture`, maps exact supported Ubuntu/Debian releases and derivative bases using case, regex and associative arrays (L16-L115). Greps GitHub latest-release JSON for a `.deb` URL, fetches via `curl -LO`, invokes `apt-get install -y ./file` as root/`sudo`, removes downloaded file (L117-L137).

**Strong/unique patterns (Observed).** Explicit distro/release allowlist and derivative-base translation; uses **APT** to install a local `.deb` so dependencies can be resolved rather than invoking raw `dpkg -i` without dependency handling; reports unsupported derivative details and manual path.

**Weaknesses / inferred consequences.** Parses JSON with grep regex (`grep -oP`, requires GNU grep with PCRE support); first request uses `curl -s` without `-f`, failure handling is incomplete. Local `.deb` download has no visible independent checksum/signature verification. `curl -LO` saves into current working directory with no exclusive temp name or guaranteed cleanup. Bash associative arrays imply Bash >=4; `set -e` does not solve pipeline status reliably. Assumptions about variables such as `UBUNTU_CODENAME` in derivative cases can be undefined; `set -u` is not used. APT local `.deb` installation is **not the same trust path** as installing an index-authenticated repository package.

**Assessment.** **Adopt** compatibility allowlists and local `.deb` dependency resolution; **replace** JSON grep, cwd download and unauthenticated package path. `REF-07 → PAT-ENV-001,PAT-APT-002`.

### `REF-08` — Docker: modern Debian APT source fragment

**Architecture and flow (Observed).** Documentation fragment, not an executable script: downloads armored key to `/etc/apt/keyrings/docker.asc`, sets it world-readable, writes deb822 `/etc/apt/sources.list.d/docker.sources` with `Types`, `URIs`, suite from `/etc/os-release`, `Components`, architecture from `dpkg`, and `Signed-By` to **that** key file (`docker-apt-repo.md:L5-L22`). It does not demonstrate packages being installed, preflight validation, key fingerprint verification, duplicate detection, rollback, or service lifecycle.

**Strong/unique patterns (Observed).** Modern deb822 syntax; per-repository scoped trust; architecture- and suite-specific source metadata; simple separation of key/source path.

**Weaknesses / inferred consequences.** `sudo curl ... -o /etc/apt/keyrings/...` writes directly to privileged destination, without verified key identity, temporary staging, or explicit creation of the keyring directory. A reused `.sources` filename can overwrite an incompatible definition. The supplied text ends at repository configuration and cannot prove later install behavior.

**Assessment.** **Preferred format** for a new modern Debian/Ubuntu bootstrap, with additional fingerprint verification and safe staging. `REF-08 → PAT-APT-001,PAT-SEC-003`.

### `REF-09` — Mullvad: concise one-line APT repository fragment

**Architecture and flow (Observed).** Fetches an ASCII signing key into `/usr/share/keyrings/mullvad-keyring.asc`; writes one-line `deb [signed-by=... arch=...]` source with `dpkg --print-architecture`; runs `apt update` and `apt install mullvad-vpn` (`mullvad.sh:L1-L9`). No shebang, `set` flags, preflight, argument parser, diagnostics, idempotency or health check are present in the fragment.

**Strong/unique patterns (Observed).** Simple explicit scope for the repository signing key, architecture restriction, package-manager-native installation; shorter source style remains valid for repositories that require it.

**Weaknesses / inferred consequences.** Key retrieval is not fingerprint-pinned, source writes overwrite by fixed path, no staged config, no duplicate detection or explicit error/lock handling. No controls on whether APT operates unattended or a service is started. As a fragment, it cannot establish its upstream project's full installation semantics.

**Assessment.** **Conditional acceptable** `.list` syntax for existing environments; prefer deb822 for newly managed sources where supported. Do not copy lack of checks into a production installer. `REF-09 → PAT-APT-001,PAT-SEC-003`.

## 5. Cross-reference comparison matrix

| Responsibility | Observed alternatives | Preferred default and reason | Decision |
|---|---|---|---|
| Entrypoint / truncation | Tailscale/Rust `main()` at end; Starship/chroncal top-level work | Main-at-end, functions first; test fetched script separately where possible | `DEC-001` |
| Platform | Tailscale distro mapping; Ghostty exact derivatives; Rust/dtop ELF+libc; chroncal `uname` | Exact OS/release allowlist for APT; exact target/ABI allowlist for binaries | `DEC-002` |
| Downloader | Rust curl/wget capability checks; Starship adds fetch; dtop snap-curl workaround; chroncal basic fallback | Checked curl with bounded timeouts/retries; known-supported wget fallback; never synthesize shell command strings | `DEC-003` |
| Latest release | Dux redirect then API; chroncal JSON `sed`; Ghostty JSON grep; Starship `/latest/download` | Prefer immutable/project-documented version or authenticated release manifest; validate version/asset names | `DEC-004` |
| Integrity/authenticity | dtop embedded hashes; Dux/chroncal adjacent hashes; Rust/Starship/Ghostty not visibly verifying | Trusted signed manifest or independently pinned digest; adjacent hashes only detect mismatch unless authenticated | `DEC-005` |
| Archive extraction | dtop unpack to temp/strip; chroncal temp; Starship direct final directory | Verify first; extract into fresh private dir; validate members and paths; stage final bytes | `DEC-006` |
| Install commit | dtop same-filesystem staged moves; Starship tar direct; chroncal `install` direct | Stage + single-file atomic rename (multi-file installs need explicit consistency strategy) | `DEC-007` |
| APT trust | Docker deb822 `.sources`; Mullvad `.list`; Tailscale keyring/legacy apt-key | deb822 + `Signed-By` + verified vendor key; never global `apt-key` for new repos | `DEC-008` |
| Privilege | Dux non-root; Tailscale sudo/doas; Starship late sudo; chroncal sudo fallback | Root only for specific writes; user-local default when allowed; determine escalation before mutations | `DEC-009` |
| Shell setup | dtop automatic profile editing and env file; Starship manual steps; chroncal PATH hint | Manual hint by default; opt-in marker-managed edits with preservation | `DEC-010` |
| Service lifecycle | Tailscale enables/starts on selected backends; other references mostly silent | Explicit enable/start/restart policy with post-start health verification | `DEC-011` |
| Diagnostics | Tailscale unsupported system report; rustup actionable TTY; dtop shadowing | Short contextual error + remediation, no secrets, no fabricated success | `DEC-012` |
| Temporary files | Dux private dir; dtop per-target staging; Starship unsafe fallback | `mktemp` hard requirement, cleanup trap, conservative permissions | `DEC-013` |
| Idempotency | dtop PATH duplicate guard; chroncal same target; APT fragments rewrite | Desired-state checks + compare-before-replace, conflicts fail before mutation | `DEC-014` |
| Bootstrapping | Rust/Dux execute downloaded installers; others install actual binary | Only if a second stage adds real value; authenticate before execution | `DEC-015` |

## 6. Reusable pattern catalog

**Catalog reading:** `Core` means normally mandatory; `Conditional` depends on scenario; `Optional` adds value in defined cases; `Rejected` must not be copied as-is. Evidence names identify **observed examples**, not blanket endorsements. Each entry specifies mechanism, preconditions/dependencies, failure and security behavior, portability, tradeoffs, and verification.

### `PAT-BOOT-001` — Main-at-end bootstrap barrier · **Core**

- **Purpose / applicability:** Reduce early side effects if a streamed installer is truncated. **Evidence:** `REF-01:L19-L22,L738-L740`; comparable `REF-02:L70,L921-L930`.
- **Mechanism:** Define all functions and constants first; put **only** `main "$@"` as the last substantive command. Main returns a nonzero status or calls `die` on failure. Under `curl | sh`, this prevents execution if the script never reaches the invocation; it does **not** authenticate the script or detect every truncation.
- **Preconditions / dependencies:** Correct interpreter, shell parsing, function definitions before `main`. **Failures/security:** A syntactically complete but malicious stream still executes; truncated streams can sometimes contain syntactically valid early code if entrypoint isn't fully last. Avoid any mutating initialization before `main`.
- **Portability / tradeoff:** POSIX-compatible; minimal cost. **Alternative:** Download whole script, verify identity, then execute (preferred for privileged systems). **Verification:** `TEST-BOOT-01` truncate script before `main` and assert no side effects.

### `PAT-BOOT-002` — Small verified second-stage bootstrap · **Conditional**

- **Purpose / applicability:** Shell only selects and launches a complex native installer. **Evidence:** `REF-02:L70-L213`; `REF-06:L58-L97`.
- **Mechanism:** Determine target, fetch native installer to private directory, verify its identity, pass args as `"$@"`, and propagate exit status. Define explicit downstream contract (version, expected effects, exit meanings).
- **Preconditions / dependencies:** Trust mechanism for second-stage binary, correct ABI, executable mount. **Failures/security:** Running a freshly downloaded executable is code execution; adjacent SHA files alone don't independently authenticate the publisher; second-stage behavior may not be auditable. **Portability:** Depends on target binary availability.
- **Advantages/disadvantages:** Tiny bootstrap and richer native UX; bigger trust boundary and hidden system effects. **Alternative:** Direct APT/binary installation. **Verification:** `TEST-SEC-03`, `TEST-BOOT-02` with a harmless stub; never execute untrusted second stages in analysis.

### `PAT-ENV-001` — OS/release/package-family resolution · **Core when distro-specific**

- **Purpose / applicability:** Select only a published-compatible repository/package. **Evidence:** `REF-01:L48-L362,L422-L508`; `REF-07:L20-L115`.
- **Mechanism:** Read trusted local `/etc/os-release`, normalize explicit distro and known derivatives, require documented base suite; identify `apt-get` and `dpkg` separately. Validate codename against project release matrix **before** network or mutation.
- **Preconditions / dependencies:** Local OS release metadata; exact supported mapping. **Failures/security:** Missing/contradictory metadata is an error, never an invitation to guess. Sourcing OS-controlled `/etc/os-release` as shell assignments assumes the host already trusts that file. **Portability:** Linux; derivatives require purposeful mappings.
- **Tradeoff:** Explicit correctness versus upkeep. **Alternative:** Distributor-provided base codename variable with checks; no automatic fallback to arbitrary `ID_LIKE`. **Verification:** `TEST-ENV-01` through `TEST-ENV-04`.

### `PAT-ENV-002` — CPU, userland and ABI compatibility gate · **Conditional**

- **Purpose / applicability:** Prevent selecting unusable ELF/ABI release artifacts. **Evidence:** `REF-02:L216-L600`; `REF-04:L496-L573,L1027-L1384`.
- **Mechanism:** Normalize `uname -m`, then when needed check `getconf LONG_BIT`, libc family/version and declared release target; reject unknown combinations. Support glibc/musl distinctions only when published binaries require them.
- **Preconditions / dependencies:** Defined artifact matrix and available feature probes. **Failures/security:** `uname` alone can misrepresent actual userland; a wrong target can execute incorrectly or fail. **Portability:** Complex ELF introspection is Linux/userland-dependent.
- **Tradeoff:** Safer ABI selection with real complexity. **Alternative:** Prefer documented static/musl binary for supported targets, as `REF-03:L225-L227`. **Verification:** `TEST-ENV-05`, `TEST-ENV-06`.

### `PAT-ENV-003` — Artifact allowlist gate · **Core for direct releases**

- **Purpose / applicability:** Avoid requesting nonexistent or unintended artifacts. **Evidence:** `REF-03:L16-L22,L390-L414`; `REF-04:L233-L308`.
- **Mechanism:** Map normalized `os/arch/abi` to an **explicit** filename and supported release set; reject before constructing a URL. Treat caller overrides as constrained values, not shell code.
- **Preconditions/dependencies:** Verified release naming and support matrix. **Failures/security:** Unknown target fails before download; an unrestricted asset/URL override can redirect trust. **Portability:** POSIX `case` sufficient; mapping project-specific.
- **Tradeoff:** Maintenance each release versus deterministic selection. **Alternative:** Authenticated release manifest with exact platform entries. **Verification:** `TEST-ENV-06`, `TEST-SEC-05`.

### `PAT-DEP-001` — Explicit dependency gate and scoped fallback · **Core**

- **Purpose / applicability:** Fail early and clearly when required tools are missing. **Evidence:** `REF-02:L70-L77,L625-L650`; `REF-04:L161-L170,L1419-L1439`; `REF-05:L17-L31`.
- **Mechanism:** Use `command -v`; require `mktemp`, integrity verifier, archive utility and package manager **only when their branch is selected**. Allow curl/wget fallback only if required options/semantics are supported.
- **Preconditions/dependencies:** Tool names and feature assumptions declared. **Failures/security:** Missing `sha256sum` must **fail**, not bypass digest verification (`REF-04:L1505-L1555` is a rejected counterexample). **Portability:** POSIX command tests; flags utility-dependent.
- **Tradeoff:** Clear errors, few branches; auto-installing prerequisites can create unexpected privileged changes. **Alternative:** Dependency installation as an explicit separate plan stage. **Verification:** `TEST-DEP-01` through `TEST-DEP-03`.

### `PAT-DL-001` — Bounded HTTPS download · **Core for network installers**

- **Purpose / applicability:** Transfer bytes while distinguishing HTTP/network failure. **Evidence:** `REF-02:L662-L761,L819-L832`; `REF-05:L21-L31`; `REF-04:L1448-L1494`.
- **Mechanism:** Fetch to newly created private temporary file using `curl --fail --show-error --location`, HTTPS-only redirects, certificate validation, connect/overall timeouts and small bounded retries. Fallback to capable wget if explicitly tested. Check exit code and expected output size/type when known.
- **Preconditions / dependencies:** Working CA trust, HTTPS endpoint, supported downloader flags. **Failures/security:** DNS/timeout/HTTP 4xx/5xx or partial download must not reach installation; never use `--insecure` or HTTP downgrade. **Portability:** Curl/wget options differ; choose documented minimum version.
- **Tradeoff:** Good diagnostics/recovery versus overly short timeouts on large archives; tune sizes per artifact. **Alternative:** Package manager's authenticated transport path. **Verification:** `TEST-NET-01` through `TEST-NET-06`.

### `PAT-DL-002` — Explicit version, origin and asset resolution · **Core for releases**

- **Purpose / applicability:** Deterministic download choice. **Evidence:** `REF-03:L429-L435,L533-L542`; `REF-06:L38-L54`; `REF-05:L34-L44,L120-L131`.
- **Mechanism:** Prefer pinned version or documented `/latest/download` endpoint; for dynamically discovered versions require a trusted structured manifest/API parser and strict character/shape validation. Never interpolate arbitrary server data into a shell command or a filesystem path.
- **Preconditions/dependencies:** Defined version policy and immutable release naming. **Failures/security:** API rate limits, moving `latest` and tag redirects complicate reproducibility; resolved version must appear in logs/receipt. **Portability:** POSIX pattern matching; JSON parsing needs actual parser or a project-specific trusted response contract.
- **Tradeoff:** Pinning reproducible, latest convenient. **Alternative:** Mirror allowlist; pin digest independent of mutable tag. **Verification:** `TEST-NET-05`, `TEST-IDEM-04`.

### `PAT-SEC-001` — Release-bound/pinned hash · **Core if artifact distribution uses digests**

- **Purpose / applicability:** Bind artifact bytes to an expected release. **Evidence:** `REF-04:L233-L304,L342-L346`; counterexample skip on missing tool L1496-L1563.
- **Mechanism:** Digest is embedded in a **trusted** versioned installer or supplied via an authenticated signed manifest; compute local SHA-256 and compare exact 64-hex digest. Verify before unpack/exec. No verification tool -> stop.
- **Preconditions/dependencies:** Independently trusted expected digest, `sha256sum` or documented equivalent. **Failures/security:** Protects against replaced artifact if installer/manifest is trusted; digest bundled untrusted with attacker-modified artifact offers much weaker authenticity. **Portability:** GNU checksum tool common Linux, must check.
- **Tradeoff:** Strong binding, digest update per release; signatures scale better with version churn. **Alternative:** Vendor signature + trusted public key (`PAT-SEC-003`). **Verification:** `TEST-SEC-01` through `TEST-SEC-03`.

### `PAT-SEC-002` — Adjacent checksum as error detector · **Conditional, insufficient alone for authenticity**

- **Purpose / applicability:** Detect transfer/storage mismatch for an artifact. **Evidence:** `REF-06:L71-L85`, `REF-05:L72-L85,L143-L149`.
- **Mechanism:** Download checksum and artifact from same release, require the expected entry, compare computed hash before use.
- **Preconditions/dependencies:** At least HTTPS, matching correct filename, mandatory hash utility. **Failures/security:** If both files are replaced at the origin, TLS alone cannot prove expected publisher bytes; this is **not** equivalent to independently pinned digest/signature. **Portability:** Simple Linux tooling.
- **Tradeoff:** Convenient automated validation but weaker origin compromise resistance. **Alternative:** Pin digest in trusted launcher or verify signed release manifest. **Verification:** `TEST-SEC-01`, `TEST-SEC-04`.

### `PAT-SEC-003` — Repository-scoped APT key trust · **Core for external APT**

- **Purpose / applicability:** Restrict which key can authenticate a repository. **Evidence:** `REF-08:L9-L20`, `REF-09:L1-L5`, `REF-01:L558-L562`.
- **Mechanism:** Download signing key into private staging, verify independently obtained full fingerprint, deploy readable `.asc`/`.gpg` under `/etc/apt/keyrings` for manually managed keys, write `Signed-By:` (deb822) or `[signed-by=]` (legacy one-line) source; update and install via APT.
- **Preconditions/dependencies:** Trusted key fingerprint from independent channel, APT version that supports chosen syntax, GPG for fingerprint inspection, supported suite/arch. **Failures/security:** Fail on key mismatch, source conflict, APT signature failure. **Portability:** Debian/Ubuntu-specific.
- **Tradeoff:** Scoped APT metadata trust (still not a per-package sandbox); manual key lifecycle maintenance. **Alternative:** Keyring installed by a separately authenticated distribution package. **Verification:** `TEST-APT-01` through `TEST-APT-06`.

### `PAT-FS-001` — Private workspace and unconditional cleanup · **Core for downloaded artifacts**

- **Purpose / applicability:** Prevent predictable-path collision and clean aborted installs. **Evidence:** `REF-06:L58-L61`, `REF-05:L117-L118`; negative `REF-03:L67-L75`.
- **Mechanism:** Set `umask 077`, `mktemp -d` with exclusive creation, record owner/scope, `trap` cleanup on exit and signal-to-exit with original status, validate cleanup target before `rm -rf`.
- **Preconditions/dependencies:** Secure accessible temporary filesystem. **Failures/security:** No predictable fallback. Do not follow symlinks or remove arbitrary caller-provided paths. Executing an artifact from `noexec` tmp is unsupported unless a separately safe executable staging location is chosen. **Portability:** POSIX traps; `mktemp` template details differ.
- **Tradeoff:** Tiny overhead; partial diagnostic artifacts optionally retained by explicit policy. **Alternative:** In-memory pipes only when neither authentication nor intermediate files are needed—rare for privileged installers. **Verification:** `TEST-FS-01`, `TEST-ERR-02`.

### `PAT-FS-002` — Same-filesystem staged replacement · **Core for direct binaries**

- **Purpose / applicability:** Keep current executable valid until new one is ready. **Evidence:** `REF-04:L728-L777`.
- **Mechanism:** Download/verify separately, stage fully copied executable **in destination filesystem**, correct mode, run static validation, then rename one file into its final path. Verify postcommit; retain previous version when rollback is required.
- **Preconditions/dependencies:** Exclusive destination access, trusted directory ownership, compatible `mv` semantics, sufficient disk. **Failures/security:** Per-file rename is atomic if same filesystem, **not** a multi-file transaction; target directory symlinks/shared writes need controls. **Portability:** POSIX rename concept, GNU `mv -T` only where declared.
- **Tradeoff:** Safe single-file activation; extra copy/storage, careful upgrade/rollback policy. **Alternative:** Versioned directory + atomic symlink swap when atomic reference switch and consumers support it. **Verification:** `TEST-FS-02` through `TEST-FS-05`.

### `PAT-FS-003` — Inspect/extract archives in isolation · **Core for archives**

- **Purpose / applicability:** Avoid archive traversal and unexpected file writes. **Evidence:** `REF-05:L151-L152`, `REF-04:L375-L387`; both have limited validation, motivating stronger requirement.
- **Mechanism:** Verify archive; inspect member names/types; reject absolute paths, `..` components, symlinks/hardlinks/devices/FIFOs unless explicitly supported and checked; extract into private directory with conservative ownership/mode; only copy an allowlisted file to final staging.
- **Preconditions/dependencies:** Known archive schema; tar/unzip implementation and flags; optional independent safe inspection tool for adversarial formats. **Failures/security:** `tar --no-same-owner` alone does not make arbitrary archives safe. **Portability:** Extractor flags differ; on GNU/Linux enforce tested GNU tar behavior.
- **Tradeoff:** More code/CPU, avoids serious security failure. **Alternative:** Distribute a single verified executable without an archive. **Verification:** `TEST-FS-06` through `TEST-FS-08` with malicious test fixtures.

### `PAT-PRIV-001` — Narrow privileged operations · **Core for system-wide installs**

- **Purpose / applicability:** Constrain root exposure. **Evidence:** `REF-01:L510-L529`, `REF-03:L174-L208`; explicit non-root boundary `REF-06:L10-L14`.
- **Mechanism:** Confirm UID and escalator before changes; select `sudo`/`doas` under explicit support policy; call exact command with `"$@"`, not an interpolated `sh -c`; download and verify as user. Require non-interactive authorization if unattended.
- **Preconditions/dependencies:** Supported privilege tool and secure system destinations. **Failures/security:** `sudo` may prompt/hang in unattended scripts; privilege failure aborts before partial mutation where possible. **Portability:** `id -u` and `sudo` common, not universal.
- **Tradeoff:** Better auditability, some extra call overhead. **Alternative:** Operator runs whole script as root only in trusted, controlled image-building workflow with documented assumption. **Verification:** `TEST-PRIV-01` through `TEST-PRIV-03`.

### `PAT-PRIV-002` — User-local fallback · **Conditional**

- **Purpose / applicability:** Install CLI without elevated permissions. **Evidence:** `REF-05:L133-L141`, `REF-04:L695-L705`.
- **Mechanism:** Default to `$HOME/.local/bin` (or explicit XDG-aware policy), create private owned directories, check executable search path and command shadowing; never silently substitute a different system scope after user explicitly chose one.
- **Preconditions/dependencies:** Reliable home directory, ownership, writable disk. **Failures/security:** User-local installation must not change system services or privileged files. **Portability:** Broad Linux shells, PATH differences.
- **Tradeoff:** No admin friction, may not be on PATH. **Alternative:** Explicit system scope with privilege confirmation. **Verification:** `TEST-PRIV-02`, `TEST-UX-02`.

### `PAT-APT-001` — Idempotent deb822 repository management · **Core for new APT repos**

- **Purpose / applicability:** Install packages with native dependency/release handling. **Evidence:** `REF-08:L9-L20`, `REF-09:L1-L9`, `REF-01:L542-L570`.
- **Mechanism:** Validate suite and arch; key identity check; detect conflicting old `.list`/`.sources` definitions; generate exact desired `.sources` text; compare current bytes; stage and commit key/source only when changed; refresh APT indexes after changes (or as freshness policy requires); `apt-get install` exact package/version.
- **Preconditions/dependencies:** apt/dpkg and trusted origin/key. **Failures/security:** Fail on global trust conflicts or mismatched key. Package-manager operation is not atomic/fully rollbackable. **Portability:** Modern Debian/Ubuntu, selected derivative only if repository publishes for its base.
- **Tradeoff:** Native security/update chain, installs may have maintainer-script side effects. **Alternative:** Local verified `.deb` (`PAT-APT-002`). **Verification:** `TEST-APT-01` through `TEST-APT-09`.

### `PAT-APT-002` — Verified local `.deb` via APT · **Conditional**

- **Purpose / applicability:** A one-off `.deb` with dependency resolution. **Evidence:** `REF-07:L117-L137`.
- **Mechanism:** Resolve exact published package for approved suite/arch, download privately, verify through independent trusted digest/signature, run `apt-get install -y ./verified.deb`, validate installed package name/version.
- **Preconditions/dependencies:** Compatible `.deb`, APT, independent trust binding. **Failures/security:** An ordinary local `.deb` is **not** authenticated by an APT repository Release signature; installation executes package scripts as root. **Portability:** APT Linux only.
- **Tradeoff:** Convenient for missing repo; update lifecycle must be defined. **Alternative:** Proper signed repository for repeat upgrades. **Verification:** `TEST-APT-08`, `TEST-SEC-03`.

### `PAT-IDEM-001` — Desired-state compare and conflict detection · **Core**

- **Purpose / applicability:** Reliable reruns and preservation. **Evidence:** `REF-04:L929-L959` duplicate PATH guard; file-rewrite counterexamples `REF-08`,`REF-09`.
- **Mechanism:** Classify every target as absent / identical-managed / different-managed / unmanaged-conflict; only mutate absent or explicitly owned differing targets. Compare before writing; journal changes made by this run.
- **Preconditions/dependencies:** Definition of ownership and target schema. **Failures/security:** Suppressing errors (`|| true`) is not idempotency; unmanaged state must not be erased silently. **Portability:** General.
- **Tradeoff:** Minor extra checks, prevents configuration drift. **Alternative:** Explicit force-replace that preserves backup and documents what changes. **Verification:** `TEST-IDEM-01` through `TEST-IDEM-05`.

### `PAT-IDEM-002` — Install receipt / shadowing diagnostics · **Optional**

- **Purpose / applicability:** Track a multi-tool installation and explain why installed executable cannot be found. **Evidence:** `REF-04:L68-L70,L397-L410,L810-L829`.
- **Mechanism:** Store manifest (version, trusted digest, install paths, managed files, scope), write atomically, and compare `command -v` path after install. Receipt is informational and **not** the sole source of truth.
- **Preconditions/dependencies:** Schema, safe serialization tool, write scope. **Failures/security:** Never accept receipt as authorization to delete arbitrary paths; avoid manual unescaped JSON substitution. **Portability:** Files and shell work generally; JSON tooling optional.
- **Tradeoff:** Improves upgrades/uninstall and debugging; unnecessary for tiny one-binary installer. **Alternative:** Plain text state in owned directory or no receipt if verification is direct. **Verification:** `TEST-IDEM-03`, `TEST-UX-03`.

### `PAT-SVC-001` — Policy-driven systemd activation · **Conditional**

- **Purpose / applicability:** Install/enable/start a service without unwanted downtime. **Evidence:** `REF-01:L571-L574,L586-L587` demonstrates activation; stronger policy is **Recommended**.
- **Mechanism:** Validate PID 1/systemd manager access, unit identity, service account, executable/config; deploy unit with compare-and-replace; `daemon-reload` only if unit changed; `enable`/`start`/`restart` only under declared policy; check `systemctl is-active` and service-specific health if required.
- **Preconditions/dependencies:** systemd available and usable, permissions, reliable unit/config. **Failures/security:** Container may have `systemctl` binary but no manager; restarting can interrupt service. **Portability:** systemd-based Linux only.
- **Tradeoff:** Predictability and observability, extra state complexity. **Alternative:** Install files without activation and give manual instructions. **Verification:** `TEST-SVC-01` through `TEST-SVC-07`.

### `PAT-UX-001` — Explicit piped-stdin/TTY policy · **Core if interactive**

- **Purpose / applicability:** Avoid reading script source as confirmation input. **Evidence:** `REF-02:L126-L205`, `REF-03:L271-L287`.
- **Mechanism:** In interactive mode read from `/dev/tty`; without controlling TTY fail with instruction to supply `--yes` only if it authorizes known actions. No implicit approvals. Allow `--non-interactive` only for validated non-destructive/planned operations.
- **Preconditions/dependencies:** TTY or explicit unattended policy. **Failures/security:** Script pipe consumes stdin; implicit consent is unsafe. **Portability:** Unix TTY expected, not present in many CI/container environments.
- **Tradeoff:** Extra flag handling vs reproducible automation. **Alternative:** Use CLI flags for all configuration, no prompts. **Verification:** `TEST-UX-01`.

### `PAT-UX-002` — Actionable plan and final report · **Core**

- **Purpose / applicability:** Make side effects observable. **Evidence:** `REF-03:L518-L554`, `REF-01:L473-L507`, `REF-05:L143-L163`.
- **Mechanism:** Before mutation report product/version/target, method, install scope, config/service intent; on success report **verified** files/version and required user action; on failure report failed stage and preservation status. Respect `NO_COLOR` and non-TTY streams.
- **Preconditions/dependencies:** Known intended operations. **Failures/security:** Never print auth tokens or private configuration; do not print success after `|| true`. **Portability:** `printf` portable.
- **Tradeoff:** Tiny overhead, substantial supportability. **Alternative:** Structured JSON output for machine callers if requested. **Verification:** `TEST-UX-02`, `TEST-UX-03`.

### `PAT-UX-003` — Opt-in, marker-managed PATH edits · **Conditional**

- **Purpose / applicability:** Persist an install directory in shell startup files. **Evidence:** `REF-04:L869-L1025`; lower-impact alternative `REF-03:L315-L388`.
- **Mechanism:** Default to printed instructions; if user explicitly opts in, choose exact supported shell file, preserve bytes, insert unique owned marker only once, never delete unrelated content, use correct shell syntax, and back up before migration.
- **Preconditions/dependencies:** Writable owned RC file, explicit shell selection and consent. **Failures/security:** Shell startup file is executable code; a bad insertion can break login sessions; do not automatically write to every shell profile. **Portability:** Per-shell logic required.
- **Tradeoff:** Convenient, but intrusive and error-prone. **Alternative:** No edit; tell user the `export PATH=...` line. **Verification:** `TEST-IDEM-02`, `TEST-UX-04`.

### `PAT-ERR-001` — Explicit checks, staged recovery, cleanup · **Core**

- **Purpose / applicability:** Preserve previous working state on errors. **Evidence:** `REF-02:L643-L656`; `REF-06:L58-L85`; limitations of `REF-05:L101,L163` and `REF-04:L1496-L1563`.
- **Mechanism:** Wrap critical operations with `if ! command; then die ...; fi` or `command || die`; preserve exit status, cleanup on exit/signal; restore only changes under current installer ownership and only if safe. Report partial success with concrete remediation.
- **Preconditions/dependencies:** Defined checkpoints/ownership and known return codes. **Failures/security:** `set -e` misses expected contexts, `!`, `if`, pipelines and subshells; do not use unguarded `|| true` on essential operations. **Portability:** POSIX conditional control flow.
- **Tradeoff:** Explicitness vs a few additional lines. **Alternative:** Bash `pipefail` where justified, **in addition** to explicit checks. **Verification:** `TEST-ERR-01` through `TEST-ERR-05`.

## 7. Recommended and rejected techniques

| Status | Technique | Rationale / controlling condition | Evidence |
|---|---|---|---|
| **Recommended** | Exact compatibility allowlists | Fail closed before any write; derivatives require documented mapping | `REF-01`, `REF-07` |
| **Recommended** | Main at end | Limits execution of truncated streams; not an integrity guarantee | `REF-01` |
| **Recommended** | Version-bound trusted SHA-256 or signature | Authenticates expected bytes if expectation itself is trusted | `REF-04` (hash binding); `PAT-SEC-001` |
| **Recommended** | Private staging on target filesystem | Avoid partial copy directly over executable | `REF-04` |
| **Recommended** | Scoped APT `Signed-By` | Limits repository key scope | `REF-08`, `REF-09`, `REF-01` |
| **Conditional** | Two-stage bootstrap | Only when second-stage behavior, trust, and compatibility are documented | `REF-02`, `REF-06` |
| **Conditional** | Complex ABI probing | Necessary for glibc/musl, ARM feature and mixed-bitness artifacts, not for APT-only installers | `REF-02`, `REF-04` |
| **Conditional** | Silent/`--yes` mode | Only if precise install/service actions are known and explicitly authorized | `REF-02`, `REF-03` |
| **Conditional** | Modify shell profiles | Opt-in and marker-managed; prefer instructions | `REF-04` vs `REF-03` |
| **Rejected** | `curl ... | sudo sh` / unverified second-stage execution | Executes mutable remote bytes as root without durable trust | Weakness exposed by `REF-02`, `REF-06` bootstrap boundary |
| **Rejected** | Hash bypass on missing tools | Fails open against corruption/tampering | `REF-04:L1502-L1563`, `REF-05:L146-L149` opt-out |
| **Rejected** | Adjacent hash advertised as standalone signature | Same compromised origin can replace data and digest | `REF-05`, `REF-06` |
| **Rejected** | `apt-key` / global key trust in new scripts | Broadens authentication to unrelated repositories | `REF-01:L553-L556` historical branch |
| **Rejected** | Direct remote file into trusted key/source location | Partial writes and unchecked provenance | `REF-08`, `REF-09`, `REF-01` |
| **Rejected** | Untested `tar` extraction to executable path | Overwrites and link/path traversal before validation | `REF-03`, `REF-05` |
| **Rejected** | Predictable `/tmp` fallback | Other-user collision/race | `REF-03:L67-L75` |
| **Rejected** | Shell-built downloader command in scalar string | Word splitting/globbing and lost path boundaries | `REF-03:L99-L112` |
| **Rejected** | `cmd || true` on critical outcome | Converts real failure into false success | `REF-05:L101,L163` |
| **Rejected** | Parsing arbitrary JSON with grep/sed as generic JSON | Sensitive to whitespace, escaping and format changes | `REF-05:L34-L38`, `REF-07:L117-L120` |
| **Rejected** | Blind append/rewrite, restart, `ln -sf` | Changes unmanaged state without ownership/consent | `REF-04:L767-L771`; `REF-08`, `REF-09` |
| **Rejected** | Assuming `set -e` covers all cases | Shell exceptions, non-final pipeline status, conditional contexts | Present in `REF-01`, `REF-03`, `REF-05`, `REF-06`, `REF-07` |

## 8. Canonical installer architecture

This is a **dependency graph with a recommended order**, not a claim that every installer needs every stage.

```text
INPUTS / TRUST POLICY
       |
       v
[01 parse + validate] --> [02 interaction policy] --> [03 detect platform]
                                                        |
                                                 [04 support gate]
                                                        |
[05 dependency gate] <-----------------------------------+
       |
[06 choose method/scope] --> [07 resolve version + exact artifacts]
       |                              |
[08 trust plan] <---------------------+
       |
[09 private staging] --> [10 network fetch] --> [11 authentication]
                                                      |
                                       [12 inspect / prepare files]
                                                      |
                                             [13 permission preflight]
                                                      |
                                      [14 commit install operations]
                                                      |
                                         [15 managed configuration]
                                                      |
                                    [16 conditional service lifecycle]
                                                      |
                                             [17 verify desired state]
                                                      |
                                         [18 cleanup + final report]
```

| Stage | Inputs → result | Read/write & privilege | Failure policy / verification |
|---|---|---|---|
| 01 Parse | Flags/env and defaults → validated normalized inputs | Read-only, user | Reject missing args, unknown flags, invalid version/path/options; `TEST-UX-01` |
| 02 Interaction | TTY, consent, CI policy → allowed action set | Read-only, user | No TTY and approval needed → abort; never consume piped code as stdin |
| 03 Detect | OS release, `uname`, dpkg, libc → host tuple | Read-only, user | Unknown fields remain unknown, not guessed; `TEST-ENV-*` |
| 04 Support gate | Host tuple + published matrix → selected target | Read-only, user | Unsupported → fail with details before networking/writes |
| 05 Dependencies | Selected branch → command/capability list | Read-only; optional explicit package prerequisites | Required tool/capability absent → actionable failure |
| 06 Method/scope | Package, binary, service and user intent → install plan | Read-only, user | Refuse undesired root/system scope |
| 07 Resolve | Fixed/latest version, vendor manifest → artifact/version | Network read, user | Version/filename ambiguity or unverified source → abort |
| 08 Trust plan | Publisher key/digest, metadata signing rules → proof requirement | Read-only, user | No workable proof → abort, not disable checks |
| 09 Stage | Target paths and temporary policy → exclusive private workspace | User-owned temp writes | `mktemp` unavailable → abort, no predictable fallback |
| 10 Fetch | HTTPS URL(s), size/time policy → downloaded files | Unprivileged temp writes | Bounded transient retries; partial file removed or quarantined |
| 11 Verify | Bytes + independently trusted expected identity → verified bytes | Read-only user | Any mismatch → abort before extraction/exec |
| 12 Prepare | Verified files → known staged payload | User temp or destination stage | Reject malformed archives, wrong binaries, permissions |
| 13 Preflight | All intended targets → conflict/ownership plan | Read-only; possibly `sudo -n -v` | Unmanaged conflict or insufficient privilege → abort |
| 14 Commit | Staged payload → final installed files/packages | **Narrow** root for system writes | Record each completed step; restore only reversible changes |
| 15 Configure | Desired config + existing owned state → target config | Narrow root only if needed | Compare before write, preserve unmanaged contents |
| 16 Service | Unit/config change + explicit activation policy → service state | Narrow root | Reload only on change; failed start → report and apply declared rollback policy |
| 17 Verify | Target state → observed executable/package/service outcome | Read-only user/root as required | Failure means overall failure, even if package command succeeded |
| 18 Cleanup/report | Temp files and mutation journal → exact outcome | User and narrow root for own staging | Preserve original error code; report partial changes and manual recovery |

**Universal:** 01–06, 13, 17–18 in proportion to installer scope. **Conditional:** 07–12 for direct downloads; APT delegates artifact trust to authenticated repository metadata; 15 for configuration, 16 for services. **Side-effect boundary:** no destructive or privileged write before a concrete plan, support gate and required trust resources are ready.

**State transitions:** `Uninspected → Compatible → Planned → Acquired → Verified → Staged → Committed → VerifiedInstalled`. APT package operations may have internal script side effects; classify them separately as `PackageManagerPartial` upon failure. On a postcommit validation failure, distinguish `RestoredPrevious`, `FailedPartial`, and `FailedNoChange`. Never infer global rollback merely because temp files were removed.

## 9. Core shell implementation primitives

### 9.1 Function and compatibility contracts

The next snippets are reusable **illustrative implementation primitives** and are **not** a runnable product installer. All executable examples in this subsection use **POSIX `sh` on Linux** unless explicitly labeled GNU/Linux; input values that identify real projects are intentionally not invented. A project installer must compose only relevant primitives and test them in its declared environment.

| Function / ID | Contract (input → output/exit) | Tools; fail behavior | Required tests |
|---|---|---|---|
| `die` · `REQ-020` | Message; stderr and exit nonzero | Shell `printf`; never log secrets | `TEST-ERR-01` |
| `have`, `need` · `REQ-021` | Command name → 0/1; `need` fatal | POSIX `command -v` | `TEST-DEP-01` |
| `parse_args` · `REQ-022` | `"$@"` → normalized validated options | POSIX `case`, `shift`; unknown operand fails | `TEST-UX-01` |
| `detect_apt_host` · `REQ-023` | OS metadata → `id,suite,arch` | `/etc/os-release`, `dpkg`; unsupported fails | `TEST-ENV-01` |
| `resolve_artifact` · `REQ-024` | Host tuple/version → exact allowlisted name | Project-defined manifest/case; never guess | `TEST-ENV-06` |
| `fetch_https` · `REQ-025` | Trusted HTTPS URL + staged filename → bytes | Curl declared version; delete/abort on failure | `TEST-NET-*` |
| `verify_sha256` · `REQ-026` | File + **trusted** expected digest → 0 | `sha256sum`; abort on mismatch/missing tool | `TEST-SEC-*` |
| `make_workspace`, `cleanup` · `REQ-027` | Temp base → exclusive workspace | `mktemp`, `rm`; trap all exit paths | `TEST-FS-01` |
| `run_root` · `REQ-028` | Command + discrete args → subprocess status | UID/sudo; fail if unavailable | `TEST-PRIV-*` |
| `inspect_archive` · `REQ-029` | Verified archive → allowlisted members/types | GNU tar or safe parser; reject dangerous members | `TEST-FS-06` |
| `install_binary_local` · `REQ-030` | Verified binary, target dir/name → committed file | `install`, `mktemp`, GNU `mv -T`; reject conflicts | `TEST-FS-02` |
| `put_managed_file` · `REQ-031` | Desired text, destination, ownership → no-op or replace | `cmp`, stage, rename; backup policy | `TEST-IDEM-01` |
| `ensure_apt_source` · `REQ-032` | Suite/arch/URI/key → validated managed source | `gpg`, `apt-get`, dpkg, root; conflict abort | `TEST-APT-*` |
| `service_reconcile` · `REQ-033` | Unit and allowed action policy → verified state | `systemctl` with actual manager | `TEST-SVC-*` |
| `verify_installed` · `REQ-034` | Executable/package/version expectations → success/failed | Direct path, dpkg status; never suppress failure | `TEST-IDEM-03` |
| `write_receipt` · `REQ-035` | Verified state → owned, atomic receipt | Structured serializer/known-safe format | `TEST-IDEM-03` |

### 9.2 Small POSIX core and error protocol

```sh
#!/bin/sh
# POSIX sh; Linux. Place all function definitions above the final main call.
set -eu
umask 077

have() { command -v "$1" >/dev/null 2>&1; }

die() {
    printf 'install: ERROR: %s\n' "$*" >&2
    exit 1
}

need() {
    have "$1" || die "required command not found: $1"
}

info() { printf 'install: %s\n' "$*" >&2; }

# In functions whose only output is a computed value, reserve stdout for data.
# Prefer "command || die ..." to assuming set -e handles every context.
main() {
    [ "$#" -eq 0 ] || die 'this example accepts no arguments'
    need mktemp
    need install
    need sha256sum
    info 'environment dependencies satisfied; no installation requested'
}

main "$@"
```

**Behavior:** `die` fatal nonzero, `need` succeeds only when found, no accidental stdout corrupting command substitution. **Tests:** missing command from a test-specific `PATH`, a command which returns nonzero inside `if` and inside function-call `||`, and stderr separation. **Security:** do not include credentials in diagnostic strings. `set -u` catches undefined values but use `${VAR:-}` for optional env. `set -e` remains an additional guard only; in POSIX shells, its behavior differs around `if`/`while`, `!`, `&&`/`||`, functions invoked in conditional contexts and subshells.

**Shell selection:** Bash-specific features should be selected deliberately. If using `#!/usr/bin/env bash` with Bash >=4, arrays and `[[ ]]` are available; use `set -o pipefail` for pipelines and still check statuses explicitly. Do **not** set `pipefail` in POSIX `sh`: it is non-portable. For POSIX pipeline checks, write/download to a temporary file first and evaluate producer and consumer separately.

### 9.3 Private workspace and signals

```sh
#!/bin/sh
# POSIX sh with Linux mktemp(1). Use inside a complete installer.
set -eu
umask 077
workdir=

cleanup() {
    rc=$?
    trap - 0
    if [ -n "$workdir" ] && [ -d "$workdir" ]; then
        rm -rf -- "$workdir" || printf 'install: warning: cleanup failed: %s\n' "$workdir" >&2
    fi
    exit "$rc"
}

trap 'cleanup' 0
trap 'exit 130' INT
trap 'exit 143' TERM
workdir=$(mktemp -d "${TMPDIR:-/tmp}/install.XXXXXXXX") || exit 1
```

**Contract:** Exclusive workspace is created with mode restricted by `umask`; original exit code is preserved. `rm --` assumes GNU coreutils; for non-GNU Linux, use validated absolute paths and target-specific removal. A production version must reject unsafe/untrusted `TMPDIR` (e.g., symlink or non-directory), avoid privileged use of attacker-controlled temp parents, and either document or implement `HUP` handling. `trap` portability differs: `0` is the POSIX exit trap; do not rely on `EXIT` spelling everywhere. A trap alone does not protect from `SIGKILL` or power loss.

### 9.4 HTTPS fetch and verified digest

```sh
#!/bin/sh
# POSIX sh; requires curl supporting --proto/--proto-redir,
# GNU sha256sum; caller supplies an ALREADY TRUSTED hex digest.
fetch_https() {
    url=$1
    out=$2
    case "$url" in https://*) ;; *) die 'HTTPS URL required' ;; esac
    if ! curl --fail --silent --show-error --location \
        --proto '=https' --proto-redir '=https' \
        --connect-timeout 15 --max-time 300 \
        --retry 2 --retry-delay 2 \
        --output "$out" -- "$url"; then
        rm -f -- "$out" || :
        die 'download failed; no artifact will be installed'
    fi
    [ -s "$out" ] || die 'empty artifact response'
}

verify_sha256() {
    file=$1
    expected=$2
    [ "${#expected}" -eq 64 ] || die 'invalid trusted SHA-256 length'
    case "$expected" in *[!0-9abcdefABCDEF]*|'') die 'invalid SHA-256 hex' ;; esac
    have sha256sum || die 'SHA-256 verifier required'
    result=$(sha256sum -- "$file") || die 'unable to hash artifact'
    actual=${result%% *}
    # sha256sum can prefix its output with a backslash for special filenames;
    # staging filenames are internally controlled ASCII, not user-provided.
    [ "$actual" = "$expected" ] || die 'artifact checksum mismatch'
}
```

**Inputs:** Trusted URL and exclusive workspace filename; trusted 64-hex expected digest must be supplied through a pinned/script-verified manifest, not a companion file blindly accepted as publisher authentication. **Failure:** No output may be committed after download/hash failure. **Limits:** Fixed `--max-time` may need raising for large artifacts. Curl return codes/5xx retry behavior vary; only transient conditions should be retried. A capable `wget` branch may replace curl but must be separately implemented/tested (not generated via word-split shell command string). TLS certificate validation must stay enabled. **Tests:** `TEST-NET-01..06`, `TEST-SEC-01..04`.

### 9.5 Detect supported APT platform and release

```sh
#!/bin/sh
# POSIX sh, Debian/Ubuntu only; require a trusted OS-provided /etc/os-release.
detect_apt_host() {
    [ "$(uname -s)" = Linux ] || die 'Linux required'
    [ -r /etc/os-release ] || die 'cannot read /etc/os-release'
    ID= VERSION_CODENAME= VERSION_ID=
    . /etc/os-release
    case "$ID" in
        debian|ubuntu) : ;;
        *) die "unsupported distribution: $ID" ;;
    esac
    suite=${VERSION_CODENAME:-}
    case "$suite" in
        ''|*[!a-z0-9.+-]*) die "invalid suite: $suite" ;;
    esac
    need dpkg
    arch=$(dpkg --print-architecture) || die 'dpkg arch unavailable'
    case "$arch" in amd64|arm64) : ;; *) die "unsupported arch: $arch" ;; esac
    # Project must ALSO check (ID,suite,arch) against actual published packages.
}
```

**Precondition:** `/etc/os-release` is part of a trusted system image (it is sourced as shell assignments, not downloaded metadata). Bash not needed. `ID_LIKE` is not proof of repository compatibility. Extend derivative mapping only using supplier-published base mappings, not guessed codenames. **Tests:** `TEST-ENV-01..06` with fixtures/stubs; do not overwrite the host's actual `/etc/os-release`.

### 9.6 Narrow privilege boundary

```sh
#!/bin/sh
# POSIX sh; Linux, sudo is optional only when privileged actions are needed.
run_root() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    elif have sudo; then
        sudo -- "$@"
    else
        die 'system-wide installation needs root or sudo; choose user-local scope'
    fi
}

assert_unattended_root() {
    if [ "$(id -u)" -ne 0 ]; then
        have sudo || die 'sudo is required'
        sudo -n -v || die 'non-interactive sudo authorization unavailable'
    fi
}
```

**Preconditions:** Authenticated operator and exact command/arguments, no untrusted program name. In an interactive script `sudo` may prompt; in CI use preflight `sudo -n -v` and `sudo -n --` for actual commands. Never interpolate `SUDO='sudo ...'` into strings or use `eval`. If `doas` is supported, create a separately tested branch with its accepted flags. Check destination ownership and path components before any privileged write. **Tests:** `TEST-PRIV-01..03`.

### 9.7 Atomic single-binary local installation (GNU/Linux)

```sh
#!/bin/sh
# POSIX sh syntax, GNU install/mktemp/mv, user-owned non-shared bin directory.
install_binary_local() (
    src=$1
    dir=$2
    name=$3
    case "$name" in ''|*[!a-zA-Z0-9._+-]*) die 'invalid binary name' ;; esac
    [ -f "$src" ] && [ ! -L "$src" ] || die 'verified binary missing or symlinked'
    [ -d "$dir" ] && [ ! -L "$dir" ] || die 'invalid target directory'
    target=$dir/$name
    [ ! -L "$target" ] || die 'refusing symlink target'
    [ ! -e "$target" ] || [ -f "$target" ] || die 'non-regular target conflict'
    stage=$(mktemp "$dir/.$name.stage.XXXXXXXX") || die 'cannot stage binary'
    trap 'rm -f -- "$stage"' 0
    install -m 0755 -- "$src" "$stage" || die 'staging copy failed'
    mv -fT -- "$stage" "$target" || die 'atomic rename failed'
    trap - 0
)
```

**Security / limitations:** Caller must already verify source authenticity, ownership and permissions of **every writable ancestor**, and that destination is not accessible for hostile concurrent replacement. On an adversarial multi-user filesystem, pre-checks alone have TOCTOU races; use a trusted root-owned destination or a stronger file-descriptor-based helper. This is one-file atomic replacement, **not** rollback; for upgrade recovery save a verified previous version and restore under an explicit policy. Privileged deployment is analogous but must create/stage/rename under narrowly scoped root commands; do **not** merely add `sudo` to the whole function. A service using the old binary may still require a separately authorized restart. **Tests:** `TEST-FS-02..05`, `TEST-PRIV-03`.

### 9.8 Safe configuration reconciliation

Use an ownership model rather than a blind `tee`:

```text
Input: desired bytes, exact destination, ownership marker/receipt, file mode
1. Validate destination and every ancestor; forbid symlink and file-type conflicts.
2. If absent: mark as newly owned; write private same-directory stage.
3. If present and bytes equal desired: NO-OP.
4. If present and recorded as installer-managed: back up or preserve old bytes,
   stage replacement, and rename only if its current bytes still match preflight.
5. If present but unmanaged or concurrently changed: ABORT with path and remedy.
6. On success: record owned file and expected hash in the receipt.
7. On failure: restore only the prior version whose identity was recorded.
```

`cmp -s old staged` is useful for byte equality; `cmp` is not a signature or a concurrency lock. For sensitive configuration use restrictive mode such as `0600`; for APT keyrings/sources and systemd units use readable `0644` where required. Do not copy file permissions or ownership from an untrusted archive. A plain-text receipt works for fixed known fields; if machine-readable JSON is needed, use a real serializer and atomic write rather than string `sed` substitution (`REF-04:L719-L725`). **Tests:** `TEST-IDEM-01..05`, `TEST-FS-03..05`.

### 9.9 APT repository and local-package primitives

**Contract `ensure_apt_source(origin, suite, component, arch, trusted_fingerprint, package)`**:

1. Confirm published repository support for the exact distribution/suite/arch, `apt-get` and `dpkg` presence, HTTPS origin, and project-supplied trusted full fingerprint. Reject ambiguous or existing conflicting source definitions (including `.list` and deb822 `.sources`).
2. Fetch the vendor key as an unprivileged user into private workspace; with `gpg --batch --with-colons --show-keys <keyfile>` inspect primary and relevant signing fingerprints and validate required identity against the **independently trusted fingerprint**. Do not discover the trust anchor from the same unchecked key download alone.
3. Stage the validated armored key as `.asc` (or dearmor into `.gpg` if required by supported APT), place it with root ownership/mode `0644` under `/etc/apt/keyrings` (managed manually), and ensure keyring directory is `0755` and trusted. Some distributions/package-managed keyrings use `/usr/share/keyrings` instead; align with actual lifecycle.
4. Generate **complete** desired deb822 source bytes using validated literals. Example **illustrative data only; not a runnable repository**:

```deb822
Types: deb
URIs: https://packages.example.invalid/linux/debian
Suites: trixie
Components: main
Architectures: amd64
Signed-By: /etc/apt/keyrings/example-vendor.asc
```

5. Compare against existing managed definition. If changed, stage within `/etc/apt/sources.list.d` with mode `0644` then single-file rename; record any previous bytes. Never modify an unowned file by assumption.
6. Run `apt-get update` when source/key changes, when required lists are absent, or according to explicit freshness policy. **Never ignore** failure or disable signature checks. Diagnose DNS, signature/fingerprint mismatch, unsupported suite, bad mirror or APT lock distinctly.
7. `DEBIAN_FRONTEND=noninteractive apt-get install -y -- <package>` for an explicitly preapproved unattended installation (flag syntax and package spec must be tested for supported APT). If pinning, ensure exact candidate is available via `apt-cache policy`/documented method. Package names and versions must be validated, not user-provided arbitrary apt options.
8. Verify `dpkg-query` installed state and version, and optionally executable/service state; report service activation separately. Do not promise undo of maintainer scripts or package dependency changes.

**Conflict handling:** When prior APT source URI/suite appears with different signing requirements, stop; do not auto-remove or rewrite another administrator's source file. **Recovery:** If APT update fails immediately after a newly created key/source, safely restore those specific previous managed files (or remove the just-created files) and explain possible cached-index effects. If package install fails, preserve repository state by policy, report package manager partiality and provide a manual recovery command; do not assume `apt-get -f install` or `dpkg --configure -a` is always safe to run automatically. **Tests:** `TEST-APT-01..09`.

**Local `.deb` variant:** A **verified** exact `.deb` can be installed with `apt-get install ./path.deb` to resolve dependencies (`REF-07`). This file's authenticity has to be established independently of normal APT repository metadata. APT/dpkg package scripts execute with privileged authority; this is not equivalent to unpacking a harmless archive.

### 9.10 systemd primitive

**Contract `service_reconcile(unit_name, desired_unit_bytes, activation_policy, health_command)`**:

```text
Require: systemctl exists AND systemd manager is usable; exact approved unit name.
Require: executable exists; service user/group permissions and config are valid.
Compare unit bytes; if changed, stage + replace managed unit, then daemon-reload.
if policy=leave-inactive: do not enable/start.
if policy=enable-only: enable, but do not start.
if policy=start-only: start, but do not enable.
if policy=enable-and-start: enable and start.
if policy=restart-on-change: restart ONLY if relevant executable/config/unit changed
                            AND existing service was active or policy says start.
Verify: systemctl is-active (if expected active), then app-specific readiness.
Report: state, enabled status, changed files, failure journal on startup error.
```

**Preconditions:** Systemd is actually PID 1/system manager (or accessible as intended) and `systemctl` operations are supported, not merely a binary present. Use service-specific `User=`, `Group=`, directory and credential rules; do not put secrets in unit command-line arguments. Unit validation with `systemd-analyze verify` is useful when available, but health must be checked separately. Avoid restart on no-op. **Tests:** `TEST-SVC-01..07`.

### 9.11 Installed-state, receipt, logging and options

- **Binary:** verify expected target is a regular executable and run a safe documented `--version`/`version`/`--help` command, checking status and output against version policy. A binary might be executable but incompatible at runtime. Never append `|| true` to acceptance check (`REQ-034`, `REF-05:L163`).
- **APT:** `dpkg-query -W -f='${Status} ${Version}\n' package` and require `install ok installed`, plus exact version if pinned. Package state may be `unpacked` or `half-configured`, which is failure.
- **Receipts:** write only for genuinely verified changes, with schema/version/product/scope, artifact identity and owned file list. For multi-tool partial outcomes store per-tool success, but do not claim whole install success (`REQ-035`).
- **Logging:** `info`, `warn`, `die` to stderr; stdout reserved for machine-readable responses. Offer quiet/verbose modes if useful. Color only for interactive streams, respect `NO_COLOR`. Redact tokens before logging commands. Avoid global `set -x` in installers processing credentials.
- **Arguments:** support `--help`, `--version` (if relevant), `--install-dir`, `--scope`, `--yes` or `--non-interactive`, `--no-modify-path`, `--dry-run` **only if** the dry-run faithfully avoids all state mutation. Always verify argument existence before `shift 2`, reject unknown arguments and unsafe environment overrides. Document precedence CLI > explicitly supported environment variables > defaults.
- **Shell-specific limitations:** POSIX `sh` has no portable arrays, `[[ ]]`, associative maps, process substitution, `pipefail`, or `local`. Use small subshell functions for variable isolation or choose Bash. Functions returning data via stdout should emit *only data*; logs go stderr. In Bash, prefer arrays for commands and `"${args[@]}"` rather than unsafe scalar expansion.

## 10. Scenario blueprint A — standalone binary installer

**Applicability:** One published executable, no package manager dependency, no service and no complex extracted dependencies. **Supported environment:** Must specify Linux OS, exact arches/ABI, local/system install, GNU utilities if used. **References:** `REF-03`, `REF-04`, `REF-05`. **Patterns:** `PAT-ENV-002/003`, `PAT-DL-001/002`, `PAT-SEC-001`, `PAT-FS-001/002`, `PAT-PRIV-001/002`.

| Design area | Required contract |
|---|---|
| Inputs | Project name; version (fixed/latest policy); verified `(OS,arch,ABI) → artifact URL, digest/signature`; binary filename; target dir; scope; overwrite/downgrade policy |
| Optional settings | `--install-dir`, `--version`, `--yes`, `--quiet`, `--no-modify-path`, opt-in release channel |
| Functions | `parse_args`, `detect_host`, `select_artifact`, `choose_scope`, `fetch_https`, `verify_artifact`, `stage_binary`, `commit_binary`, `verify_installed`, `cleanup` |
| Privileges | None for detection/network/hash; only root-owned directory creation and commit require `run_root`; user-local always unprivileged |
| Versioning | Resolve concrete version, validate metadata, record digest; refuse unsupported downgrade unless opted in; no-op if installed bytes/version satisfy desired state |
| Installation | Copy fully verified executable into temporary file on destination filesystem; set `0755`; check target conflicts; atomically rename; preserve old artifact if rollback policy requires |
| Configuration | Do **not** change PATH by default; print a concise check and exact proposed line; no shell init for unrelated shells |
| Verification | Check direct absolute path, executable invocation and expected version; check `command -v` if PATH discoverability is a requirement |
| Failure | Before commit: cleanup, old binary untouched. During/after commit: try restore known previous version only when owned and safe; otherwise report exact partial state |
| Idempotency | Same installed version/hash → no-op; differing managed version → upgrade; conflicting symlink/non-regular file → refuse; no duplicate PATH changes |
| Tests | `TEST-ENV-05/06`, `TEST-NET-02/05`, `TEST-SEC-01/03`, `TEST-FS-02/03/04`, `TEST-IDEM-01/03/04` |

**Algorithm:** `parse → support gate → resolve immutable artifact → select privilege/scope → fetch → authenticate → inspect payload format → preflight destination → stage → commit → verify → receipt/report`. **Known limitations:** No automatic OS package updates; glibc/musl compatibility must be matched; direct binary may have runtime dependencies not visible from architecture; not a multi-file transaction.

## 11. Scenario blueprint B — archive-based installer

**Applicability:** tar/zip release with one or several allowlisted payloads. **Supported environment:** Declare archive formats, archive schema, filenames, nested directory depths, symlink policy, extraction tool, and supported OS/ABI. **References:** `REF-03`, `REF-04`, `REF-05`; note weaknesses in all three. **Patterns:** `PAT-FS-001/002/003`, `PAT-SEC-001`.

**Execution sequence and gates:**

1. Resolve **exact** artifact name and trusted digest. Reject unsupported archive type before network.
2. Fetch archive to a private `mktemp -d` workspace, authenticate bytes **before extraction**.
3. Inspect member listing and types. Reject absolute filenames, empty/ambiguous normalized paths, `.`/`..` traversals, symlinks/hardlinks/devices/FIFOs **unless the project defines and securely validates their resolution**. Reject duplicate target paths and unexpected members where a fixed schema exists.
4. Limit number of files/expanded size where feasible; compressed archives can expand dramatically. Avoid extraction as root; never extract into `/usr/local/bin`, `/etc`, home root, or current working directory.
5. Extract to a fresh private directory, with root ownership restoration disabled. Validate actual extracted files and that resolved paths remain inside staging; require expected regular executable(s), no hidden extra payloads.
6. For a single executable, apply `PAT-FS-002`. For multiple tightly coupled files, prefer immutable version directories plus an atomic pointer to an entire version where consumers permit it, otherwise acknowledge partial-commit window and plan recovery.
7. Set modes/owners explicitly. Update only managed links and metadata; atomically write receipt after success.
8. Run executable/version and dependent-file checks. On failure restore previously known working version if a safe mechanism exists.

**Function decomposition:** `inspect_archive`, `extract_archive`, `validate_tree`, `stage_payloads`, `commit_payloads`, `verify_layout`. **Privilege:** unprivileged extraction; root only final target. **Idempotency:** compare released files/manifest, do not repeatedly extract or rewrite on no-op. **Failure:** reject archive before mutation; backup previous version if supported. **Tests:** `TEST-FS-06/07/08`, `TEST-SEC-02`, `TEST-ERR-03`, `TEST-IDEM-04`. **Limitation:** no generic `tar` flag set alone guarantees adversarial archive safety; for complex untrusted archives use a reviewed extraction library/helper with path validation and resource limits.

## 12. Scenario blueprint C — APT repository bootstrap

**Applicability:** Publisher-maintained signed APT repository; packages need updates/dependency integration. **Supported environment:** Explicit Debian/Ubuntu versions, suites, architectures, key formats, APT version and vendor repo matrix. **References:** `REF-08` (deb822), `REF-09` (one-line), `REF-01` (multi-distro APT branch). **Patterns:** `PAT-ENV-001`, `PAT-APT-001`, `PAT-SEC-003`, `PAT-PRIV-001`, `PAT-IDEM-001`.

| Step | Read-only checks and authorized effects | Failure / acceptance |
|---|---|---|
| 1 Support | `/etc/os-release`, suite, `dpkg --print-architecture`, exact vendor matrix | No guessing derivative suite; fail unsupported |
| 2 Preflight | Validate package name and version, APT lock context, root availability, current `.list`/`.sources` definitions | Report conflicts before any write; do not delete lock files |
| 3 Trust anchor | Obtain **independently verified vendor fingerprint** or trusted package for key | Unknown/mismatch → abort |
| 4 Download key | User-owned exclusive staging via HTTPS; fingerprint inspect | Any download/identity failure → no privileged mutation |
| 5 Source plan | Generate validated deb822 `Types/URIs/Suites/Components/Architectures/Signed-By` | Validate key path, no duplicate URI/suite conflict |
| 6 Reconcile | Compare bytes; commit key and source as root through checked temp files; journal changed paths | No-op on same state; backup/restore installer-owned prior bytes |
| 7 Index refresh | `apt-get update` only if needed by change/freshness policy | Abort on signature, mirror, suite, lock failure; report partial state |
| 8 Package install | `apt-get install -y <approved-package>` with explicit unattended consent; optionally version pin | Do not suppress failure or run broad repair automatically |
| 9 Verify | `dpkg-query` package installed/version + expected executable/service state | Distinguish package present from working service |
| 10 Report | Summarize origin/suite/arch, package version, key identity, service policy, changed files | Never claim all operations rolled back |

**Privilege boundaries:** Unprivileged for discovery, key fetch and key fingerprint inspection; root only for `/etc/apt` writes, `apt-get update/install`. **Idempotency:** no duplicate source, no key rewrite if identical, no package operation if installed state already meets explicit policy and freshness permits. **Upgrades:** let APT handle authenticated updates; pinned version requires candidate availability and downgrade policy. **Failure recovery:** restore newly written source/key upon source-validation or initial update failure where safe, but package installation can leave dependency/configuration changes—report rather than fabricate rollback. **Tests:** `TEST-APT-01..09`, `TEST-PRIV-01`, `TEST-IDEM-02/03`. **Limitations:** Vendor repository and signing keys can rotate; APT Release signatures authenticate repository metadata and packages via hashes, but do not sandbox package scripts. Publishing a key fingerprint on the same mutable download origin is not an independent trust anchor.

**Key rotation requirement (`REQ-036`):** If trust key changes, require vendor-authenticated transition (e.g. old-key-signed transition or separately verified new fingerprint). Never silently trust a new key merely because the URL returns it. **Source ownership (`REQ-037`):** Do not silently migrate unrelated distro-managed entries or delete legacy source files of unknown provenance.

## 13. Scenario blueprint D — personal development-tools installer

**Applicability:** Several independent CLI tools for one user, optionally with shell integration. **Supported environment:** Linux user account with trusted home and writable bin/config; set per-tool arch/ABI and trust metadata. **References:** `REF-04`, `REF-03`, `REF-05`. **Patterns:** `PAT-PRIV-002`, `PAT-IDEM-001/002`, `PAT-UX-002/003`, `PAT-FS-002`.

**Inputs:** Tool manifest records `{name, exact version/version policy, source, trusted digest/signature, install path, verify command, dependencies}`; `--only`/`--skip` tool controls, user-local base directory, optional PATH policy. All manifest fields must be project-authenticated or hardcoded and reviewable. **Function decomposition:** `load_manifest`, `topological_order`, `install_one`, `verify_one`, `record_result`, `report_summary`, optionally `manage_path`.

**Sequence:**

1. Resolve dependency graph; detect cycles and unsupported targets **before** installation. Keep tools independent where possible.
2. For each selected tool, decide no-op / upgrade / new; verify independently, stage in user-owned directories and commit individually.
3. Distinguish **mandatory** tools (failure aborts dependent work) from optional tools (failure recorded, continue independent work). Never report overall success when a mandatory tool failed.
4. Preserve configuration; no forced RC edits. If PATH integration opt-in, append one marker-owned line at most; detect command shadowing and show actual path.
5. Record per-tool installed version, trusted artifact identity and status; verify direct binary invocation for every selected mandatory tool.
6. Summarize `N installed`, `M current`, `K failed` with names and actionable retry paths.

**Privilege:** none by default; system-wide scope must be separately selected and authorized, not inferred. **Idempotency:** same manifest → all no-ops; resume partial run by comparing actual state. **Recovery:** individual tool replacement can preserve previous binary; aggregate installation intentionally not global atomic. **Tests:** `TEST-IDEM-01..05`, `TEST-UX-02/03/04`, `TEST-FS-03`. **Limitations:** Dependency cycles and conflicting binary names require explicit rules; storing receipts is not enough to determine installed truth.

## 14. Scenario blueprint E — systemd service installer

**Applicability:** Executable with a daemon or long-running server and optionally service account/configuration. **Supported environment:** Explicit Linux+systemd manager; declare package/binary installation method, service unit and account ownership. **Reference:** `REF-01` service starts; safe reconcile model is **Recommended**, not observed in full reference code. **Pattern:** `PAT-SVC-001`.

**Inputs:** Exact executable identity, unit name/content, `User=`/`Group=` rules, state/config directories, environment/config schema, restart behavior, activation policy (`inactive`, `enable`, `start`, `enable-and-start`, `restart-on-change`), readiness check and expected port/socket if applicable.

**Sequence:**

1. Check systemd is the active service manager. `systemctl` installed alone is insufficient (containers, chroots, WSL variants).
2. Install/verify executable first; create dedicated least-privileged service account where required (guard collision with existing user/group and handle UID/GID policy).
3. Create owned runtime/state/config dirs with restrictive modes. Stage/default config; never overwrite existing user-modified config without migration.
4. Validate unit and relevant paths; deploy managed unit via compare/stage/replace. Avoid exposing secrets in `ExecStart=` command arguments or verbose logs.
5. Run `systemctl daemon-reload` if unit files changed (or effective unit state needs refresh).
6. Apply only the **authorized** enable/start/restart action. If only executable changed and policy says no restart, report that running daemon may still be old version.
7. Verify `is-enabled` only when enablement was required, `is-active` only when active state was required, and application readiness independently (e.g. documented local health endpoint).
8. If start fails: collect *safe* journal/systemctl status diagnostics, preserve existing configuration, restore prior unit/executable if safe and policy requires, report any pending recovery.

**Functions:** `detect_systemd`, `ensure_service_account`, `ensure_state_dirs`, `reconcile_unit`, `maybe_reload`, `apply_activation_policy`, `check_readiness`. **Privilege:** account/dir/unit/service operations only, not network. **Idempotency:** no `daemon-reload` or restart if nothing meaningful changed; preserve running state per policy. **Tests:** `TEST-SVC-01..07` in a systemd-enabled VM or suitable privileged integration runner. **Limitations:** A started unit can become unhealthy later; script tests only bounded readiness, not continuous availability.

## 15. Scenario blueprint F — hybrid system installer

**Applicability:** APT repo/packages plus direct artifacts, config files and systemd units. **Supported environment:** All constraints of relevant child blueprints; prefer Debian/Ubuntu and explicit versions. **References:** Composite design inspired by `REF-01`,`REF-04`,`REF-08`; **not** claimed to be fully implemented in a supplied sample.

**Directed acyclic operation plan:**

```text
[host / privilege / trust preflight]
       |
[authenticate vendor key and binary artifacts]
       |
[APT source reconcile] -> [APT metadata refresh] -> [install APT dependencies]
                                                   |
                                   [stage+install direct executables]
                                                   |
                                   [managed configuration / accounts]
                                                   |
                                     [unit file reconcile / reload]
                                                   |
                                    [optional service activation]
                                                   |
                                         [final state validation]
```

**Required operation descriptor:** `ID`, dependencies, expected input state, target owner, mutation type (read-only, file-reversible, APT-nontransactional, service-interruptive), verification probe, compensation if safe, and failure message. Maintain a simple human-readable plan in shell; only introduce a generic dependency engine if installer breadth justifies it.

**Failure boundaries:**

| Failure position | Required behavior |
|---|---|
| Preflight/trust acquisition | Abort with no privileged mutations |
| Key/source reconcile | Restore exact prior **owned** bytes if safe; do not affect unmanaged sources |
| APT update | Fail; optionally restore newly added source/key, state that cached index may remain |
| APT package install | Abort dependents; report package-manager partial state and manual recovery; no fictitious undo |
| Binary staging | Keep current binary, clean stage; APT dependencies may already be installed |
| Config/unit reconcile | Restore individually owned reversible files under recorded policy; report earlier package changes |
| Service activation | Do not restart repeatedly; capture status/readiness and identify whether previous service is still running |
| Final verify | Return nonzero; list exactly what is valid, what failed, and what remains changed |

**Inputs:** Configuration manifest, pinned trust anchors, package order, install versions, approval flags, service policy, support matrix. **Functions:** `build_plan`, `preflight`, child-blueprint functions, `journal_change`, `recover_safe_changes`, `verify_all`, `report_partial`. **Privileges:** stage first and apply narrow root changes in order. **Idempotency:** each substep converges independently; repeated run resumes after a partial failure. **Testing:** full `TEST-INT-01/02`, all APT, service and safety subtests. **Limitation:** **no globally atomic transaction** across APT, files, user/group changes and service manager; partial success must be first-class output.

## 16. Security and trust model

### 16.1 Trust levels are not interchangeable

| Mechanism | What it establishes | What it does **not** establish | Default policy |
|---|---|---|---|
| HTTPS with valid CA/TLS | Encrypted/authenticated transport to an HTTPS endpoint under the Web PKI | That endpoint is uncompromised, that binary is publisher-authorized, reproducibility | **Mandatory** for direct HTTP retrieval; no insecure fallback |
| SHA-256 of downloaded file vs adjacent `.sha256` | File matches the separately downloaded digest | Independent publisher authenticity if both come from same mutable origin | May be supplementary only |
| SHA-256 vs digest pinned in a trusted installer/manifest | Bytes match the trusted expected artifact digest | Safety of executable; absence of vulnerabilities; lifetime of trust channel for pinned file | **Recommended** for fixed binaries |
| Verified release signature with trusted public key | Signed bytes/manifest authorized by holder of trusted signing key | Trustworthiness of the signer or safety of signed code | **Recommended** when project provides verifiable signatures |
| APT `InRelease`/`Release.gpg` + `Signed-By` | Repository metadata signed by authorized key; package hashes anchored in signed metadata | Harmless package scripts, secure runtime, independent key provenance | **Mandatory** for third-party APT |
| Root privileges | Permission to change protected system state | Authenticity or correctness of content being installed | Minimize and delay |

**Threat scenarios:** malicious or compromised release origin; compromised mirror/CDN; MITM or broken TLS trust; malicious archive member; symlink race; malicious environment overrides; untrusted local state; incorrect/rotated APT key; repository suite mix-up; partial network transfer; unsafe package maintainer script; unintended service activation. Not all can be eliminated by shell: define an acceptable publisher trust model and residual risks.

### 16.2 Mandatory security rules

- **`REQ-038` URLs and redirects:** Require HTTPS and enforce HTTPS-only redirects for direct downloads, validate host allowlist where appropriate. Do not use `curl -k`, `wget --no-check-certificate`, or arbitrary scheme redirects to fix a failing install.
- **`REQ-039` Authenticity gate:** Verify the **entire downloaded artifact** before extracting, executing, installing, or passing to package manager. If no trustworthy digest/signature is available, **stop and document the unsatisfied requirement**; the project can choose a properly authenticated APT package or provide a verified artifact.
- **`REQ-040` APT trust:** The full vendor signing fingerprint (or other authenticated key transition) must be established out of band. Do not trust a key merely because it came over TLS from the same repository URL. Use `Signed-By` scoped to intended repository; never recommend `trusted=yes`, `--allow-unauthenticated`, or global `apt-key add` for a new repository.
- **`REQ-041` Permissions:** Workspaces `0700` with `umask 077`; secrets `0600`; executables normally `0755`; public key/source/unit files typically `0644`; root-owned system paths owned by root. Apply mode and ownership explicitly, not inherited from an untrusted archive.
- **`REQ-042` Filesystem validation:** Check destination and parent ownership/mode, file type, symlinks (including broken symlinks), writable ancestry, reserved paths and collisions. Avoid user-writable staging for privileged target replacement. Treat TOCTOU limits explicitly.
- **`REQ-043` Archive safety:** Reject traversal, absolute paths, invalid members, unsafe links, unexpected modes and excessive extraction sizes; extract as non-root. A verified hash does not mean an archive is *structurally* safe.
- **`REQ-044` Data and command injection:** Quote every path/argument; validate user-supplied version/arch/repo/suite; never use `eval`, unsafe dynamic `sh -c`, string-built commands, or unquoted JSON/API output as shell. Do not unconditionally source remote configuration.
- **`REQ-045` Privilege:** Never authenticate/unpack user-controlled bytes as root unnecessarily. Execute signed APT package scripts as root only after repository trust has been established and install explicitly authorized. Redact credentials.
- **`REQ-046` Remote-script UX:** For `curl -fsSL URL | sh`, the script should be easy to audit, restrict pre-main effects and not depend on stdin for prompts. Be candid: the shell pipeline may report only the last process's status; a complete locally verified download and separate execution is safer, especially for privileged installs.
- **`REQ-047` Environment:** Explicitly allowlist installer environment overrides (`INSTALL_DIR`, `VERSION`, `TMPDIR`, proxy settings). Treat them as inputs; restrict unsafe paths/URLs, unexpected parameter expansion and inheritance into root commands.

**On failed security requirements:** Do **not** continue, ask for a known-good key/digest or reject unsupported mode. Do not silently switch to HTTP, unverified tar, `--allow-unauthenticated`, or an unrelated repository. A user explicitly requesting insecure shortcuts must be told the trust model cannot be satisfied by this standard.

## 17. Error handling and recovery

### 17.1 Error taxonomy and response

| Error | Retry? | Abort/continue | Safe recovery |
|---|---|---|---|
| DNS transient, connection reset, 429/503/504 as classified by client | Yes, bounded with backoff and max total time | Abort after budget | Delete partial artifact; unchanged final state |
| 404 artifact/unsupported release, invalid version | No | Abort | Correct target/version mapping, no writes |
| TLS certificate failure, wrong signature/hash, unexpected key | **Never** | Abort immediately | Preserve old install; alert about trust mismatch |
| Archive invalid or dangerous | No | Abort | Remove staging; no extraction to target |
| Missing commands/unsupported distro/ABI | No | Abort | Install explicit prerequisites or provide supported method |
| Permission denied / sudo unavailable | No automated retry | Abort | User-local alternative or operator authorization |
| APT lock held | No blind loop; optional bounded deliberate wait | Abort or later retry as user policy | Do **not** remove lock files |
| APT signature/index update failure | Only transient transport; not signature failure | Abort | Restore own just-written key/source if policy safe |
| Package installation/maintainer-script failure | No generic blind retry | Abort dependent stages | Inspect `dpkg` state; manual repair may be needed |
| New executable fails postcommit verification | No generic retry | Abort/report failed | Restore verified prior binary if policy and ownership permit |
| Existing unmanaged target differs | No | Abort pending consent | Leave user file untouched |
| Service startup/readiness failure | One specifically allowed restart/retry may be appropriate | Abort or report partial | Journal/diagnostics; optional known-safe prior version restore |
| Optional independent tool fails | Depends on error | Continue only if policy declares optional | Record failed tool; overall partial status |
| Cleanup fails | No attempt to re-run entire install | Preserve primary exit status; warn | Report retained temp path, but never expose secrets |

**Implementation rules (`REQ-048`):** Capture the failure stage and return code. No bare `|| true` for required steps. Preserve the original failure through cleanup. Use `if command; then ... else ... fi` where `set -e` behavior is ambiguous. For a pipeline in POSIX `sh`, split into separately checked operations. For execution signals, use exit traps and signal-specific statuses; no guarantee on `SIGKILL`/power loss. Use bounded network retries rather than arbitrary `sleep` loops.

### 17.2 Rollback capability classification

| Change type | Typical reversal | Guarantee |
|---|---|---|
| Temp workspace only | Remove own temp tree | Usually reversible unless interrupted/cleanup fails |
| Single versioned file prior to rename | Remove staged file | Existing file stays valid |
| Single file after rename with saved old bytes | Rename known prior artifact back | Possible if target ownership/paths remain safe; still not seamless for already-running processes |
| Two or more binary/config files | Individual restoration | **Not atomic as a group** unless version-directory pointer design is valid |
| New key/source owned by this installer | Restore previous owned bytes or remove just-created file | Reversible files; APT caches/other activity may persist |
| APT package install | Package-manager repair/removal | **No reliable generic rollback**; maintainer-script effects may persist |
| User/group creation | Manual account/state decision | Potentially referenced by external files; do not automatically delete on failure |
| systemd service activation | Stop/disable/revert unit depending on authorized policy | Not necessarily restores lost availability or state |

### 17.3 Crash recovery protocol

On restart, examine **actual** installed binary/package/config/unit state. Reconcile from desired version/manifest, not a `started` marker. If a previous transaction has a private staging directory, do not delete it based solely on name; determine ownership and guard against symlink/race. If a journal exists, treat it as a hint requiring validation. A new run may continue completed stages, but does not implicitly authorize destructive repair. Preserve meaningful diagnostics and avoid retries that compound a partially configured APT state.

## 18. Idempotency and upgrade management

`REQ-049` For each target, implement the following decision state machine:

| Observed state | Desired state/action | Required result |
|---|---|---|
| Absent | New install | Create exactly once, verify, record ownership |
| Same managed version **and trusted hash** | Re-run | No-op with successful verification; no download needed if proof still valid and policy permits |
| Managed, older | Upgrade | Obtain/verify new bytes; stage and commit; no unrelated config reset |
| Managed, newer | Default re-run | Preserve; report newer version; reject downgrade without explicit policy |
| Managed, damaged/incomplete | Repair | Verify trusted desired artifacts and repair only owned targets; report actions |
| Unmanaged regular file | Install conflict | Stop and show path; do not assume overwrite permission |
| Symlink/broken symlink/directory at target | Install conflict | Stop unless documented symlink migration is explicitly authorized |
| Existing config identical | Re-run | No-op, no needless restart |
| Existing config changed by user | Upgrade | Preserve; opt-in merge or fail with diff/backup path |
| Existing APT definition identical | Re-run | No duplicate source, no unnecessary rewrite |
| Existing source for same URI/suite with different `Signed-By` | Bootstrap | Fail and request reconciliation; do not add conflicting definition |
| Existing service already active, no change | Re-run | Leave running; no restart or redundant `enable` |
| Staged interrupted install | Repair | Verify actual destination and staged ownership, then re-stage or safely discard own residue |

**Version comparison:** Shell lexical comparison is insufficient for semantic/debian versions. For APT use `dpkg --compare-versions` where required; for direct releases use project-specific version parser or exact digest equality. **Pinning** must be separate from **downgrading**: a pinned version older than installed software must not trigger accidental downgrade. `latest` is a moving pointer; record the concrete resolved release and digest.

**Receipts:** Managed-file receipt can help identify ownership, but actual file state still controls. A missing receipt is not blanket authorization to overwrite. Reconcile hidden side effects such as shell RC edits, aliases, source list files and systemd unit changes individually.

## 19. Linux portability and operational assumptions

### 19.1 Declared environment matrix

| Dimension | Debian/Ubuntu default | Variants requiring specific design |
|---|---|---|
| Interpreter | `/bin/sh` (often dash) | Bash >=4 if associative maps/arrays needed; declare explicitly |
| Package manager | `apt-get`, `dpkg` | Other managers need separate audited branch; do not probe-and-guess |
| `/etc/os-release` | Present on supported modern releases | Derivatives may provide base-release fields; exact map required |
| Architecture | `dpkg --print-architecture` | Direct ELF binary also needs libc/ABI/word-size checks |
| Download tool | curl (chosen minimum version), possible wget fallback | Restricted curl snap, BusyBox wget, missing CA store |
| Tools | GNU coreutils/tar in Debian | BusyBox/GNU option mismatches; `mv -T`, `sha256sum`, `install` not universal |
| systemd | Common but not assured | Containers/chroots/WSL may have binary but no running manager |
| Root escalation | root session or `sudo` | `doas` requires a tested branch; CI uses `sudo -n` |
| Temporary path | Private `mktemp -d`; honor safe TMPDIR | `/tmp` may be `noexec` or capacity-limited |
| Filesystem | Local writable ext4/xfs/etc | NFS, overlayfs, cross-filesystem moves, symlinked directories, RO mounts |
| Network | Valid CA trust, HTTPS, redirect support | Proxies/captive portals, rate limits, IPv4/IPv6, offline image builds |
| Terminal | Optional `/dev/tty` | `curl | sh`, CI and remote noninteractive sessions |

### 19.2 POSIX `sh` and Bash decision guide

| Need | POSIX `sh` | Bash |
|---|---|---|
| Single CLI download / APT setup | Preferred, small functions + `case` | Allowed, not necessary |
| Arrays of filenames or command arguments | Positional parameters or careful decomposition | Prefer real arrays to unsafe strings |
| Associative distro maps | `case`, small explicit lists | Associative arrays (Bash >=4) may simplify extensive maps |
| Pipeline failure detection | Check stages separately, avoid producer pipe into privileged write | `set -o pipefail` with explicit status checks |
| Function-scoped vars | Subshell functions or careful variable discipline; `local` is non-POSIX | `local` and arrays built in |
| Error traps | POSIX exit/signal traps | `ERR` and `BASH_SOURCE` possible but semantics must be tested |
| Command substitution | Removes trailing newlines; exit status must be checked | Same caveats; `pipefail` may help but not universal |
| Interpreter availability | `/bin/sh` generally foundational | Bash can be absent in minimal containers |

**Portability requirement (`REQ-050`):** No mixing `[[ ]]`, `source`, arrays or `local` into a script labeled strictly POSIX. If adopting Rust/dtop's widely supported `local` extension under `#!/bin/sh`, it must be **explicitly documented as non-POSIX** and tested on all declared shells; preferably choose Bash or avoid the extension. GNU-specific external flags are not POSIX shell features—document both.

## 20. Testing methodology and detailed test matrix

### 20.1 Test environments and safety

- **Static, no execution of installer:** `sh -n installer.sh` and `dash -n installer.sh` for POSIX profile, or `bash -n` for Bash; ShellCheck with correct `-s sh`/`-s bash`; review quote patterns, pipeline status, `set -e` and signals. Use formatter only if it preserves intended behavior. **Note:** ShellCheck was not available in the current working environment; no claim of a ShellCheck pass is made.
- **Unit/mock:** Mock shell commands in a temporary `PATH` and use fixtures for API/version metadata, OS-release logic, download failures and file conflicts. Test functions without pointing them at real `/etc` or `/usr` destinations. Avoid `eval`-based mocks.
- **Container:** Run clean/repeated APT install tests in **disposable** Debian/Ubuntu images with an isolated, authenticated test repository. A container without systemd must not be used to assert service activation works.
- **VM:** Use a disposable systemd-enabled VM/snapshot to test real service, package-maintainer side effects, reboot/start state, interruption and rollback. Never use the evaluator's live host for destructive failure injection.
- **Publisher/prod-like target:** Verify actual release artifacts, keys/ABI on controlled test hardware only after full trusted-source review. Static test execution does not substitute for provenance/authenticity verification.

### 20.2 Test cases

Each row states **preconditions → procedure → pass/fail oracle**. Tests should fail the build if the stated outcome is not observed. IDs are stable and map to patterns/requirements above.

| Test ID | Scenario and preconditions | Procedure | Expected pass condition / failure oracle | Level |
|---|---|---|---|---|
| `TEST-BOOT-01` | Stream truncated before trailing `main` | Feed a shortened harmless script stub to declared shell | No mutation or installer main invocation; non-success result or no reported success | Mock |
| `TEST-BOOT-02` | Second-stage stub returns 17 | Download local-fixture verified stub, invoke with multiple quoted args | Args preserved, outer installer returns 17, temp cleaned | Mock |
| `TEST-ENV-01` | Debian supported suite | Supply OS fixture / stub architecture | Correct tuple; no distro guessing | Unit |
| `TEST-ENV-02` | Ubuntu supported suite | Supply supported fixture | Correct suite and arch; correct vendor mapping | Unit |
| `TEST-ENV-03` | Derivative with ambiguous base | Supply ID/ID_LIKE without verified mapping | Explicit unsupported failure, **no writes** | Unit |
| `TEST-ENV-04` | Missing/malformed os-release or unknown codename | Inject malformed fixtures | Fail before privileged/network work | Unit |
| `TEST-ENV-05` | x86_64 kernel / 32-bit userland, or glibc below minimum | Mock architecture/libc probes | Reject wrong artifact; no 64-bit executable attempted | Unit/container |
| `TEST-ENV-06` | Unknown CPU/ABI, unsupported release | Modify host tuple/manifest fixture | Target selection fails closed, no guessed URL | Unit |
| `TEST-DEP-01` | `sha256sum` absent | Prepend controlled `PATH` lacking checksum tool | Hard failure before install; no verification bypass | Mock |
| `TEST-DEP-02` | curl absent, capable wget present | Replace tools with wrappers | Chosen fallback completes securely; errors propagated | Mock |
| `TEST-DEP-03` | Neither downloader or required archive tool present | Isolate `PATH` | Actionable failure before artifact use | Mock |
| `TEST-NET-01` | DNS failure | Stub downloader to return DNS error | Bounded attempts, failure report, target unchanged | Mock |
| `TEST-NET-02` | Connect/transfer timeout | Stub slow/timeout responses | Timeout bounded, temp removed, target unchanged | Mock |
| `TEST-NET-03` | HTTP 503 then success | Stub response sequence | Bounded retry succeeds only after verification | Mock |
| `TEST-NET-04` | HTTP 404/missing artifact | Stub 404 | No pointless indefinite retries; no install | Mock |
| `TEST-NET-05` | Partial or zero-byte download | Return nonzero with partial file; or zero body | Abort, partial removed; never execute/extract | Mock |
| `TEST-NET-06` | HTTP redirect to insecure scheme | Stub or local test endpoint | HTTPS-only redirects reject scheme downgrade | Mock/integration |
| `TEST-SEC-01` | Known expected hash and bytes | Calculate hash, then alter one byte | Good file accepted, modified file rejected; target unchanged | Unit |
| `TEST-SEC-02` | Malformed expected digest | Feed empty/short/non-hex digest | Fail before trusting artifact | Unit |
| `TEST-SEC-03` | Downloaded executable with invalid/missing trusted proof | Feed unverified artifact fixture | No execution, no apt local package install | Mock |
| `TEST-SEC-04` | Key signature/fingerprint mismatch | Swap APT test key or manifest signature | Reject before source or package mutation | Container/mock |
| `TEST-SEC-05` | Malicious URL/version/filename input | Include whitespace, slash, `..`, shell metacharacters and option prefix | Input rejected or treated as inert literal; no arbitrary command/path | Unit |
| `TEST-FS-01` | Workspace path with spaces, normal exit and SIGTERM | Create safe fixtures and signal stub | Only owned temp deleted; correct exit status; no unrelated file removed | Mock |
| `TEST-FS-02` | Existing correct binary | Re-run same version/digest | No rename/rewrite, healthy final verification | Container |
| `TEST-FS-03` | Destination readonly / insufficient disk | Fail stage or commit via injected wrapper | Existing binary remains valid, failure stated | Mock/container |
| `TEST-FS-04` | Target is symlink, broken link or directory | Create conflict fixtures | Refuse unowned collision; no target-following writes | Mock/container |
| `TEST-FS-05` | Interrupt during stage and during commit | Signal mock at specific stages | Before commit old binary valid; after commit state truthfully reported; recovery safe | VM/mock |
| `TEST-FS-06` | Archive has `../` or absolute paths | Inspect hostile fixture, do not extract to real host | Archive rejected before target mutation | Unit/container |
| `TEST-FS-07` | Archive contains symlink/hardlink/device/fifo | Inspect hostile fixture | Unsupported member rejected even with good package hash | Unit/container |
| `TEST-FS-08` | Archive duplicates targets or extraction bomb | Use safe bounded fixtures | Reject schema and/or resource limit before final write | Unit/container |
| `TEST-PRIV-01` | No root/sudo in system scope | Run mocked UID and escalator | Fails early; no privileged mutation | Mock |
| `TEST-PRIV-02` | User-local installation without sudo | Use isolated HOME and PATH | Completes without root and writes only owned targets | Container |
| `TEST-PRIV-03` | Unattended sudo credentials unavailable | Run with `sudo -n` mock failure | Fail without prompt/hang; preserve state | Mock |
| `TEST-APT-01` | Clean supported repository install | Disposable OS + test signed repo | Exact deb822 `Signed-By`, correct arch/suite; authenticated package installed | Container |
| `TEST-APT-02` | Same repo already configured identically | Run twice | No duplicate files, no needless rewrite/update if freshness allows | Container |
| `TEST-APT-03` | Existing conflicting `.list`/`.sources` | Supply duplicate URI/suite with differing key | Refuse conflict, leave old config unchanged | Container |
| `TEST-APT-04` | Vendor key fingerprint differs | Serve alternate key | Reject before key/source commit | Container |
| `TEST-APT-05` | Missing/expired/wrong apt signature | Serve invalid signed metadata | `apt-get update` failure not ignored, no unauthenticated install | Container |
| `TEST-APT-06` | Repository suite/arch unavailable | Configure unsupported matrix or absent Release file | Reject before installing package | Container |
| `TEST-APT-07` | dpkg/apt lock held | Coordinate two package processes safely in test VM/container | No lock deletion, bounded failure or waiting policy | Container |
| `TEST-APT-08` | Verified local `.deb` with dependencies | Stage known-good signed/pinned file | APT resolves dependencies; query installed state/version; unverified file refused | Container |
| `TEST-APT-09` | Package maintainer script fails | Use benign test package that intentionally returns failure | Overall nonzero, reports partial dpkg state, no false rollback claim | Container |
| `TEST-SVC-01` | No systemd PID 1/manager | Run in ordinary non-systemd container | Installer refuses activation or follows documented inactive policy | Container |
| `TEST-SVC-02` | New managed unit, activation authorized | Install fixture service in disposable VM | Unit syntax valid; daemon-reload, enable/start only per policy | VM |
| `TEST-SVC-03` | Unit/config unchanged and service running | Rerun installer | No needless reload/restart, correct active state | VM |
| `TEST-SVC-04` | Unit or executable changed, restart permitted | Change managed fixture | Exactly authorized reload/restart, readiness passes | VM |
| `TEST-SVC-05` | Policy leave inactive | Install new fixture | Installed but not auto-enabled/started | VM |
| `TEST-SVC-06` | Service startup fails | Return nonzero from benign ExecStart fixture | Overall nonzero; journal/status and preserved config reported | VM |
| `TEST-SVC-07` | Missing service user / bad directory ownership | Inject bad service permissions | Detect/repair only authorized owned state, fail readiness if unresolved | VM |
| `TEST-IDEM-01` | Clean → rerun | Invoke twice with same manifest | Second run converges/no changes and still verifies | Container |
| `TEST-IDEM-02` | Preexisting user-edited config, rc file, APT source | Supply unmanaged contents | Contents unchanged absent explicit migration | Container |
| `TEST-IDEM-03` | Install version exact; receipt corrupted/missing | Delete/edit receipt, inspect actual binary/package | Trust actual state; no accidental destructive overwrite | Container |
| `TEST-IDEM-04` | Upgrade and explicit downgrade | Start from previous/newer versions | Upgrade works; downgrade denied unless authorized, older version recoverable if policy | VM/container |
| `TEST-IDEM-05` | Interrupted partial hybrid run | Fail after package or first binary step, rerun | Completed stages detected; safe resume; no claimed global transaction | VM/container |
| `TEST-ERR-01` | Essential command fails in conditional/pipeline | Inject errors into fake downloader/copy/hash | Nonzero propagates; success never logged | Mock |
| `TEST-ERR-02` | SIGINT/SIGTERM | Send signal during safe staging | Proper error/status and cleanup, old target remains where applicable | Mock |
| `TEST-ERR-03` | Verification fails after commit | Stub binary to fail version/readiness | Overall nonzero; rollback or exact failed state reported | Mock/VM |
| `TEST-ERR-04` | Cleanup itself fails | Make own temp undeletable in test sandbox | Original failure code preserved; cleanup warning | Mock |
| `TEST-ERR-05` | Optional tool fails in multi-tool run | Declare tool optional and make it fail | Independent work continues; partial summary identifies failure | Mock |
| `TEST-UX-01` | Piped noninteractive stdin, confirmation needed | Pipe harmless script; no `/dev/tty` | Clear refusal; `--yes` only works for documented consent | Mock |
| `TEST-UX-02` | PATH missing, whitespace in path | Install to isolated `$HOME/.local/bin` | No broken quoting; accurate PATH instructions | Container |
| `TEST-UX-03` | Installed binary shadowed | Put earlier dummy binary on PATH | Warn with correct paths; do not falsely claim command resolution | Mock |
| `TEST-UX-04` | Opt-in PATH edit applied twice | Start with RC fixture | Exactly one marked entry; user content intact | Mock |
| `TEST-INT-01` | Full hybrid clean install | Disposable OS + signed test repo + benign service | Every declared state verified; correct ownership and no unapproved activation | VM |
| `TEST-INT-02` | Full hybrid rerun/upgrade/failure | Snapshot, induce failure after APT then rerun | Accurate partial state, no duplicate config, safe resumability | VM |

**Pass threshold (`REQ-051`):** All tests applicable to the declared installer category and supported environment must pass; skipped tests require documented scope rationale. **Security-sensitive tests cannot be waived because the check is difficult.** `REQ-052` Record exact interpreter/package versions and test commands, outputs, exit codes, artifact hashes and environment images in CI logs **without secrets**. No claim that the above tests have been executed is made.

## 21. Engineering decision tables

These are **choice algorithms**, not recommendations to choose everything simultaneously. IDs refer to the cross-reference comparison in §5. Project-specific requirements override a default only when they do not undermine mandatory trust/correctness controls.

| Decision | Conditions | Recommended choice | Rationale, exceptions and patterns |
|---|---|---|---|
| `DEC-001` Interpreter | Simple env check, CLI flags, APT/binary operations; no arrays | POSIX `sh` | Small footprint; **Bash** if arrays/complex mapping or `pipefail` materially simplify code (`PAT-BOOT-001`, `REQ-002`) |
| `DEC-002` Platform probe | APT repository; direct ELF archive | OS release+dpkg for APT; target+ABI allowlist for ELF | `uname` alone insufficient for ABI; exact vendor matrix mandatory (`PAT-ENV-*`) |
| `DEC-003` HTTP client | Capable curl available; otherwise suitable wget; neither | curl; tested wget fallback; fail if neither | Do not auto-install curl with root without explicit plan (`PAT-DL-001`) |
| `DEC-004` Version choice | Reproducible production install; interactive convenience | Pin concrete version+digest; allow latest only under documented policy | Mutable latest requires resolved version recorded (`PAT-DL-002`) |
| `DEC-005` Artifact trust | Trusted digest/signature; adjacent digest only; none | Verify trusted signature/pin; adjacent digest supplementary; fail if no adequate proof | Never equate checksum co-hosted with artifact to signature (`PAT-SEC-*`) |
| `DEC-006` Archive | Known format and expected members; unknown/malicious | Inspect, isolate and extract as user; otherwise fail | Direct extraction into final destination rejected (`PAT-FS-003`) |
| `DEC-007` Replacement | One binary; coupled multi-file tree | Single same-FS rename; version-dir switch or documented partial rollback for tree | `mv` across FS can copy then delete (`PAT-FS-002`) |
| `DEC-008` APT source | New modern repository; legacy supported older environment | deb822 `.sources` + scoped `Signed-By`; `.list` conditional | Never new global `apt-key` (`PAT-APT-001`) |
| `DEC-009` Scope/privilege | User-only CLI; system package/service | User-local unprivileged; narrow `sudo` for system writes | Whole-script root only for explicitly controlled build environments (`PAT-PRIV-*`) |
| `DEC-010` Shell config | CLI not in PATH; auto-setup opt-in | Print manual line; marker-managed change only on consent | No shotgun edits to multiple RC files (`PAT-UX-003`) |
| `DEC-011` Service policy | User did not request activation; user explicitly requested running daemon | Leave inactive; activate only if approved | Restart-on-change only if explicitly authorized (`PAT-SVC-001`) |
| `DEC-012` UX | Terminal; CI/no TTY | Prompt via `/dev/tty` where meaningful; documented noninteractive flags in CI | Never read installer source from stdin (`PAT-UX-001`) |
| `DEC-013` Temporary state | `mktemp` available; no `mktemp` | Exclusive `mktemp` workspace; otherwise fail | No predictable `/tmp` names (`PAT-FS-001`) |
| `DEC-014` Existing target | Same managed, different managed, unmanaged | No-op; upgrade/backup; conflict error | No hidden overwrite (`PAT-IDEM-001`) |
| `DEC-015` Second stage | Shell complexity large and verified native installer available | Thin authenticated launcher | Otherwise direct install avoids a new execution trust boundary (`PAT-BOOT-002`) |
| `DEC-016` Dependency handling | Tool absent; package user approved; install can be deferred | Fail with prerequisite, or explicit dependency stage | No surprise root modifications (`PAT-DEP-001`) |
| `DEC-017` Retry | Temporary connection/5xx; 404; hash/key failure | Bounded retry; abort; abort | Never retry security mismatches to make them disappear (`PAT-DL-001`, `PAT-ERR-001`) |
| `DEC-018` Rollback | One owned file, backed up; APT package/scripts; multiple service steps | Restore owned bytes; fail-and-report partial state; compensating recovery only where sound | No false transaction promises (`PAT-FS-002`, `PAT-ERR-001`) |
| `DEC-019` Config | Identical; managed changed; unmanaged changed | No-op; backup+replace; preserve and fail | Respect actual ownership (`PAT-IDEM-001`) |
| `DEC-020` Package method | Authenticated vendor repo available; verified one-off `.deb`; portable single static binary | APT; local APT install; direct binary respectively | Prefer lifecycle appropriate to update/service requirements (`PAT-APT-001/002`, `PAT-FS-002`) |
| `DEC-021` Unsupported system | Unknown distro/ABI or unsupported release | Fail before modification, show detected metadata | Do not silently substitute another distro's packages (`PAT-ENV-001/003`) |
| `DEC-022` Index refresh | Source/key changed or metadata stale; unchanged and sufficient metadata | Refresh; otherwise may skip | `apt-get update` cost justified by correctness; no unconditional skip (`PAT-APT-001`) |

**Tradeoff resolution:** Security/correctness requirements outrank convenience. Among safe equivalents, prefer the simplest option with less mutable state and fewer dependencies. No invented numeric quality score is used.

## 22. Future coding-agent implementation contract

> **Instruction to the implementing agent:** Treat this section as an executable workflow checklist. Do not copy reference code wholesale. First create a project-specific plan; then select and implement the smallest applicable subset of this specification.

### 22.1 Agent workflow

1. **Classify** request as A/B/C/D/E/F, or a justified combination. Record exact program, intended install result and whether installer invocation may be `curl | sh`.
2. **Gather facts:** authoritative artifact/repo URLs, exact published versions and names, supported Linux/ABI/distribution matrix, signing key fingerprint or pinned digest, service name and configuration contract. If facts are missing and cannot be verified, leave the action blocked **rather than inventing values**.
3. **Choose interpreter:** `sh` by default; use Bash only with a documented material benefit, minimum version and syntax validation.
4. **Specify trust:** distinguish TLS, artifact digest, signatures, APT repository identity and publisher compromise. Name the actual trust anchor and its provenance.
5. **Specify scope:** user-local or system-wide, who authorizes privileged operations, exact destinations and ownership boundaries.
6. **Inventory current state:** existing binary/package/version, repo sources/keys, config, shell profiles, symlinks, units and active services. Define ownership/conflict behavior for each.
7. **Create stage plan:** map applicable `PAT-*` to explicit required function contracts, `REQ-*` and `TEST-*`. Mark privileged operations and irreversible package effects.
8. **Implement:** functions small, single-responsibility and composable. Use named helpers for detection, downloading, verification, staging, configuration, service and verification; avoid abstractions unrelated to this installer.
9. **Check failures:** network, source trust, no TTY, missing dependency, invalid archive, path collision, no sudo, APT locks, interruption, postcommit failure.
10. **Prove idempotency:** clean install, re-run, already-current, upgrade, failed midway and re-run. Preserve user configuration and no-op service state.
11. **Validate interpreter/tooling:** syntax and ShellCheck on exact shell target; review all external utility flags for supported distributions. Do not present lint as proof of correct behavior.
12. **Test:** run applicable unit/mocks and integration/VM cases in §20 with recorded results. Do not run third-party scripts merely to analyze their design.
13. **Review security:** inspect all privileged writes, file types, archive traversal, keys, TLS options, shell quoting, source metadata, secrets in logs and runtime code paths.
14. **Deliver:** executable script, help/usage, supported platform matrix, trust-anchor documentation, all assumptions, state-change summary, known limits, test report and recovery guidance.

### 22.2 Requirements precedence and prohibited shortcuts

Apply **(1)** explicit verified project-specific requirements, **(2)** mandatory security/correctness constraints, **(3)** applicable blueprint requirements, **(4)** conditional recommendations, **(5)** optional enhancements. If explicit requirements conflict with essential safety (e.g. unchecked root-level code execution), identify the conflict and request a safer alternative rather than silently complying.

The agent **must not** fabricate URLs, digests, fingerprints or distro mappings; silently skip verification; disable TLS or APT signatures; unconditionally run as root; assume every host has `sudo`, curl, Bash or systemd; rewrite unmanaged config; automatically enable services without policy; mask important errors; claim all failures roll back; call a rerunnable script idempotent without state tests; claim to have executed tests it did not run.

### 22.3 Required implementation handoff schema

```yaml
# Template only. Values must be established for each real project.
installer_category: A|B|C|D|E|F
interpreter: /bin/sh | /usr/bin/env bash
minimum_shell_version: <when relevant>
supported_linux: <exact distro/release/arch/ABI matrix>
installation_method: <apt-repo|local-deb|binary|archive|hybrid>
install_scope: <user|system>
artifact_manifest: <authoritative source + concrete version + filenames>
trust_anchor: <pinned-digest|signed-manifest|apt-repository-key fingerprint>
privileged_operations: <exact command and target paths>
managed_targets: <owned files, permissions, and conflict rules>
version_policy: <new|same|upgrade|downgrade|repair>
path_policy: <none|manual-guide|opt-in-marker>
service_policy: <inactive|enable|start|enable-and-start|restart-on-change>
partial_failure_policy: <what can and cannot be restored>
verification: <binary/package/config/unit/readiness assertions>
applicable_patterns: [PAT-ENV-001, ...]
applicable_requirements: [REQ-001, ...]
applicable_tests: [TEST-ENV-01, ...]
limitations: <known unsupported cases>
```

If an item is inapplicable, state **not applicable** rather than inventing a placeholder implementation. Do not publish a production installer with unresolved trust or target matrix fields.

## 23. Objective acceptance checklist

Each checkbox must be independently verifiable in the resulting project. Blank means not yet evidenced; `N/A` requires a recorded reason. Use it as the final gate for an AI agent.

### Interpreter, support and input

- [ ] `REQ-002/050`: Shebang and syntax agree; declared shell works with its actual version; syntax/lint results recorded.
- [ ] `REQ-001/023/024`: Every supported OS/release/arch/ABI maps to an exact published artifact or repository; unknown targets fail before writes.
- [ ] `REQ-021/022`: Every selected external tool is checked; all flags and environment overrides validated; missing args/unknown options fail.
- [ ] `REQ-018/046`: `curl | sh` mode, if supported, avoids pre-main side effects and never reads the script pipe for confirmations.

### Download, authenticity and privilege

- [ ] `REQ-003/025/038`: All network fetches use checked HTTPS with enforced TLS/redirects and documented bounded timeout/retry behavior.
- [ ] `REQ-012/026/039`: Required hash/signature missing, malformed or mismatched results in nonzero exit **before** install/execution.
- [ ] `REQ-040/036`: APT key identity and rotation policy independently established; sources use scoped `Signed-By`; no global `apt-key`/unchecked repository.
- [ ] `REQ-004/028/045`: Downloads/hash/extraction run without root; each root operation is enumerated; unattended sudo behavior tested.
- [ ] `REQ-015/047`: Secrets, tokens and unsafe env overrides cannot leak to logs or redirect privileged operations.

### Filesystem, APT, service and state

- [ ] `REQ-027/041`: Temporary files exclusive/private, cleanup hooks installed, original failure status preserved and unsafe fallback absent.
- [ ] `REQ-029/043`: Every archive is verified and structurally inspected before unprivileged isolated extraction.
- [ ] `REQ-014/030/042`: Parent and target file types/ownership checked; symlink conflicts refused; applicable binary commits use same-filesystem staging.
- [ ] `REQ-013/031/037`: Existing unmanaged config, APT entries, RC files and aliases preserved unless separately authorized; changed managed files staged and compared.
- [ ] `REQ-032`: APT suite/arch/source conflicts covered, authenticated index errors propagated, installed dpkg state/version checked.
- [ ] `REQ-033`: Service manager availability proven; service enable/start/restart exactly matches policy; no unnecessary reload; readiness checked.
- [ ] `REQ-005/049`: Re-run, same, upgrade, downgrade and interrupted states have defined and tested outcomes.
- [ ] `REQ-006/048`: Rollback boundaries documented; package-manager and service effects never falsely described as atomic.

### Verification, user experience and test evidence

- [ ] `REQ-009/020/034`: Errors report stage/remedy without secret leaks; no success reported until executable/package/service verification passes.
- [ ] `REQ-035`: Receipt, if used, is atomically generated and cannot authorize arbitrary deletions; actual state is inspected on rerun.
- [ ] `REQ-010/017`: Final acceptance includes direct installed executable or authoritative dpkg/service checks, not download/rename status alone.
- [ ] `REQ-051/052`: Applicable unit, failure injection, container and VM tests executed and recorded; skips justified; no invented test claims.
- [ ] Project documentation lists supported environments, trust provenance, update/downgrade, uninstall or manual recovery, noninteractive/service semantics and every known limitation.

## 24. Known limitations and unresolved project decisions

1. **Source snapshots only:** No signatures, actual artifact bytes, second-stage executables, full Docker/Mullvad installers or repository contents were supplied. A reference's success behavior cannot be inferred from the shell alone.
2. **Upstream drift:** Versions and published distro support can change. Validate source manifests against the **actual project and release being installed** before shipping a new script.
3. **Publisher trust anchors:** No new project's independently authenticated fingerprint, signing key, release manifest or immutable digest is provided. An agent cannot fill these from memory.
4. **User-specific policy:** Supported distributions, install scope, opt-in profile editing, service actions, downgrade restrictions, unattended privilege and failure rollback all require project decisions.
5. **Archive safety:** Shell+tar alone is not a general-purpose adversarial archive extraction sandbox. For hostile/unbounded archive formats, use safer reviewed helper tooling.
6. **Power loss/concurrency:** POSIX shell has no global transactional filesystem/package/service model. Concurrent installers need a separate ownership/locking plan; `flock` is acceptable on declared Linux but not assumed universal. Power loss can leave a partial staged or package state.
7. **APT package scripts:** Even cryptographically authenticated packages can run privileged install hooks with arbitrary effects. APT signatures establish provenance of repository metadata, not code safety.
8. **Future repository formats:** Deb822 and per-source keys are current recommended patterns for modern APT, but actual target APT version and vendor publishing support must be verified before use.
9. **No benchmark or scored comparison:** The reference set supports qualitative tradeoffs; empirical reliability or performance rates were not measured.
10. **Validation performed for this *document* is not installer test execution:** Syntax checks on illustrative snippets, if recorded below, do not establish runtime correctness of any supplied installer.

## 25. Evidence, traceability and implementation appendix

### 25.1 Source map and high-value line pointers

| Reference | Primary evidence anchors | Derived pattern / decision / requirements / tests |
|---|---|---|
| `REF-01` Tailscale | `tailscale.sh:L19-L22` main-last; `L48-L210` distro map; `L397-L429` network/support; `L510-L575` root/APT; `L589-L630` DNF versions | `PAT-BOOT-001,PAT-ENV-001,PAT-APT-001,PAT-PRIV-001 → DEC-002,DEC-008,DEC-009 → REQ-001,REQ-032,REQ-040 → TEST-ENV-01,TEST-APT-01` |
| `REF-02` rustup | `rust.sh:L70-L213` bootstrap/TTY; `L216-L600` architecture; `L625-L761` checks/download; `L819-L919` TLS capabilities | `PAT-BOOT-002,PAT-ENV-002,PAT-DL-001,PAT-UX-001 → DEC-003,DEC-015 → REQ-021,REQ-025 → TEST-BOOT-02,TEST-NET-02,TEST-UX-01` |
| `REF-03` Starship | `startship.sh:L67-L75` temp; `L89-L152` download/unpack; `L174-L208` privilege; `L217-L269` target; `L271-L313` UX; `L390-L414` allowlist | `PAT-ENV-003,PAT-UX-002` and rejected temp/extract → `DEC-006,DEC-013 → REQ-027,REQ-029 → TEST-FS-01,TEST-FS-06` |
| `REF-04` dtop | `dtop-install-script.sh:L233-L304` hash mapping; `L496-L573` glibc; `L728-L777` staging; `L810-L829` shadow; `L869-L1025` PATH; `L1496-L1571` hash-skip | `PAT-SEC-001,PAT-FS-002,PAT-UX-003` → `DEC-005,DEC-007,DEC-010 → REQ-012,REQ-030 → TEST-SEC-01,TEST-FS-02` |
| `REF-05` chroncal | `chroncal-install-script.sh:L21-L38` downloader/version; `L72-L85` checksum; `L96-L115` install; `L117-L163` traps/install/verify | `PAT-DL-001,PAT-SEC-002,PAT-FS-001 → DEC-005,DEC-013 → REQ-026,REQ-027 → TEST-SEC-01,TEST-ERR-02` |
| `REF-06` Dux | `dux.sh:L10-L36` gates; `L38-L54` latest; `L58-L97` fetch/hash/execute | `PAT-BOOT-002,PAT-DL-002,PAT-SEC-002 → DEC-004,DEC-015 → REQ-039 → TEST-BOOT-02,TEST-SEC-03` |
| `REF-07` Ghostty | `ghostty.sh:L20-L115` distro map; `L117-L137` API grep/local `.deb` APT | `PAT-ENV-001,PAT-APT-002 → DEC-002,DEC-020 → REQ-023,REQ-032 → TEST-ENV-03,TEST-APT-08` |
| `REF-08` Docker | `docker-apt-repo.md:L9-L20` deb822 `Signed-By` | `PAT-APT-001,PAT-SEC-003 → DEC-008 → REQ-032,REQ-040 → TEST-APT-01,TEST-APT-04` |
| `REF-09` Mullvad | `mullvad.sh:L1-L9` key/signed-by/arch/update/install | `PAT-APT-001,PAT-SEC-003 → DEC-008 → REQ-032,REQ-040 → TEST-APT-01,TEST-APT-03` |

### 25.2 Detailed crosswalk examples

- **`REF-04:L233-L304,L1496-L1563 → PAT-SEC-001 → DEC-005 → REQ-012/026/039 → TEST-DEP-01 + TEST-SEC-01`.** Observation: embedded per-artifact hashes, but function skips checks when tools are absent. Recommendation: mandatory trusted hash verification with fail-closed tooling.
- **`REF-08:L9-L20 + REF-09:L1-L9 + REF-01:L553-L562 → PAT-SEC-003/PAT-APT-001 → DEC-008 → REQ-032/036/040 → TEST-APT-01/03/04/05`.** Observation: scoped key examples coexist with obsolete global trust branch. Recommendation: deb822 and independently validated signing-key identity.
- **`REF-04:L728-L777 + REF-03:L188-L208 → PAT-FS-002 → DEC-007 → REQ-030/042 → TEST-FS-02/03/05`.** Observation: target-local staging reduces direct overwrite risk. Recommendation: full validation before a single atomic rename and explicit multi-file consistency policy.
- **`REF-02:L193-L205 + REF-03:L271-L287 → PAT-UX-001 → DEC-012 → REQ-018/022/046 → TEST-UX-01`.** Observation: `/dev/tty` for prompts in script-pipe environments. Recommendation: fail without controlling TTY if approval is required.
- **`REF-01:L19-L22 + REF-06:L58-L97 → PAT-BOOT-001/002 → DEC-001/015 → REQ-018/039 → TEST-BOOT-01/02`.** Observation: main-at-end and verified-adjacent-digest bootstrap. Recommendation: integrity barrier plus **independent** artifact trust, not pipe-level assumed integrity.

### 25.3 Static validation commands for a future installer

```sh
# Run against a NEW installer under development; never run supplied sources to analyze them.
sh -n ./install.sh
# If POSIX compatibility is claimed:
dash -n ./install.sh
# If deliberately Bash:
bash -n ./install.bash
# When ShellCheck is available:
shellcheck -s sh ./install.sh
# or: shellcheck -s bash ./install.bash
```

**Review every `# shellcheck disable=...`** with a local rationale. Syntax checks prove only parseability, not security or correct source resolution. End-to-end verification requires real safe artifact fixtures, controlled package repositories and disposable VMs.

### 25.4 Document-use instruction

For a small installer, apply §§1–2, the relevant reference lessons in §4, the applicable patterns in §6, §8–9, **one** scenario blueprint in §§10–15, trust/failure/idempotency in §§16–18, and the applicable tests/checklist in §§20–23. For hybrid work, use the explicit operation graph in §15. Do not copy the entire reference catalog into a new 50-line script. The correct product is a **small installer with demonstrably correct behavior**, not a universal installer framework.

