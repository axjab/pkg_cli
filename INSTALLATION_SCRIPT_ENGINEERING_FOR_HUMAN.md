# Installation Script Engineering Guide

**For human developers and reviewers** · **Linux-first, with Debian/Ubuntu/APT priority** · **Companion technical contract:** [`INSTALLATION_SCRIPT_ENGINEERING_BLUEPRINT.md`](INSTALLATION_SCRIPT_ENGINEERING_BLUEPRINT.md)

## 1. What makes a good installer?

A good installer changes the intended system **and nothing else**. It can describe what it will do, select the right release, verify what it downloaded, preserve existing state, recover where possible, and clearly report when it cannot. A short installer is preferable to a framework, provided its safety properties are explicit.

The strongest ideas in the nine supplied references come from different places: Tailscale's distribution-aware dispatch and main-at-end structure; Rust's careful architecture and piped-stdin handling; dtop's target-local staging and embedded release hashes; Starship's clear interactive plan; chroncal's compact function decomposition; Ghostty's exact derivative compatibility rules; Docker and Mullvad's scoped APT signing keys. None of these reference scripts should be copied unchanged as a universal template. Some contain weak practices such as unchecked archive extraction, adjacent-only checksums, permissive verification fallback, outdated global APT keys, or unsafe overwrite semantics.

The **standard** is: correct on declared supported platforms, secure by defined trust rules, predictable when rerun, and honest about partial failure. It does **not** promise that all Linux systems work or that an APT installation can be rolled back like a file rename.

## 2. Recommended installer lifecycle

<small>*Only include the steps needed by the installer category.*</small>

```text
1. Parse and validate inputs (including version and install scope)
2. Detect OS, release, architecture and any relevant libc/ABI
3. Reject unsupported targets and missing dependencies
4. Choose installation method and establish trust requirements
5. Resolve a concrete artifact or authenticated package source
6. Download into a private temporary workspace, as non-root
7. Verify authenticity/integrity BEFORE extracting or executing
8. Check destination ownership, conflicts and existing version
9. Stage changes; commit only validated, owned targets
10. Apply configuration and services ONLY under explicit policy
11. Independently verify the executable, package or service
12. Clean up and report exact outcome, including partial changes
```

**Key boundary:** No privileged mutation should happen before compatibility, intended changes, and required trust checks are understood. For a signed APT repository, APT verifies packages through signed repository metadata. For a directly downloaded binary, the installer needs its own trusted signature or pinned digest.

## 3. Choosing the installation method

| Situation | Default choice | Why |
|---|---|---|
| Publisher maintains an authenticated APT repository | **APT with `Signed-By`** | Dependency and update integration; correct platform packages |
| Publisher distributes a verified `.deb`, no repository | **Verified local `.deb` via `apt-get install`** | Resolves dependencies, but update policy must be supplied |
| Single portable CLI binary | **Verified standalone binary** | Small, fast, minimal package-manager and privilege footprint |
| Tar/zip of multiple files | **Verified archive + isolated inspection/extraction** | Allows layout control; extra extraction and consistency risks |
| Personal collection of CLI tools | **User-local per-tool installer** | Avoids root, supports independent update/failure handling |
| Daemon or background service | **Package/binary installation + explicit systemd policy** | Separates files installed from service enabled/running |
| Several interdependent operations | **Hybrid with ordered stages** | Enables accurate partial failure and safe re-execution |

Prefer a supported, signed distribution mechanism over custom download logic when the product's lifecycle requires it. APT and direct binary installation solve related but not identical problems.

## 4. Shell selection

Use `#!/bin/sh` when `case`, small functions, command checks and basic filesystem operations are sufficient. It is a good default for Debian/Ubuntu bootstrap scripts and minimal images.

Use Bash when it **materially simplifies** the implementation—for example, many arrays of artifact arguments, associative mappings, or pipeline status handling with `pipefail`. Declare the minimum Bash version and test it. `local`, arrays, `[[ ... ]]` and `source` are **not POSIX sh**. Some supplied scripts use `#!/bin/sh` with the widespread but non-POSIX `local` extension; do not accidentally describe that as portable POSIX.

Always quote path arguments, avoid string-built commands and `eval`, and check important return codes explicitly. `set -e` does not capture every failure—especially in conditional functions and pipelines. In POSIX `sh`, avoid pipelines into privileged file writes; download to a checked file first.

## 5. The patterns worth reusing

| Pattern | Practical rule | Example evidence |
|---|---|---|
| **Compatibility gate** | Require an exact supported distro/suite or binary target before download | Tailscale, Ghostty, rustup |
| **Private workspace** | `umask 077`, exclusive `mktemp -d`, cleanup on exit/signals | Dux, chroncal |
| **Checked network transport** | TLS validation, HTTP error checks, bounded timeouts/retries | rustup, dtop |
| **Independent trust binding** | Trusted pinned digest, signed manifest, or scoped authenticated APT metadata | dtop hashes; Docker `Signed-By` |
| **Destination-local staging** | Copy complete bytes to target filesystem, then rename a single executable | dtop |
| **Minimal privileges** | Download/verify without root; elevate only for protected writes | Tailscale, Starship |
| **State-aware no-op** | Compare actual target and managed configuration before modifying | dtop's duplicate PATH guard |
| **Clear UX** | Show version, platform and destination; use `/dev/tty` for piped interactive prompts | Starship, rustup |
| **Verified outcome** | Run installed program/version check or query dpkg/service state | Required improvement over weak end checks |

For most new single-CLI installers, these fit in a few small functions: `detect`, `select_artifact`, `download`, `verify`, `install`, `verify_installed`, `cleanup`.

## 6. Security essentials

**Five independent questions should be answered before shipping:**

1. **Transport:** Is download HTTPS with certificate validation and HTTPS-only redirects?
2. **Authenticity:** Why are these bytes trusted? A SHA-256 file downloaded beside the archive detects inconsistencies but does not independently prove publisher identity. Pin the digest in a trusted script or verify a signature using an already trusted key.
3. **Repository identity:** For external APT, is the complete key identity independently verified and restricted with `Signed-By`? Modern deb822 `.sources` is preferred for new repositories; never add vendor keys to global `apt-key` trust.
4. **Privileges:** Can downloads, checksum verification and archive inspection run without root? Are root operations enumerated rather than applying `sudo` to the whole installer?
5. **Filesystem:** Are paths, owners, symlinks and archives checked before writing? An archive may contain traversal paths or links even if its digest is valid.

**Do not use security bypasses to improve apparent success:** `curl -k`, APT `trusted=yes`, `--allow-unauthenticated`, missing-hash skips, unverified remote binaries executed as root, or unchecked extractions into `/usr/local/bin`.

For `curl URL | sh`, place functions above a final `main "$@"` call and avoid reading prompts from the script's stdin. This reduces one class of truncated-stream failure, but it does **not** secure the downloaded script. For high-trust/system installs, downloading and verifying the whole installer before execution is preferable.

## 7. Idempotency, upgrades and error handling

An installer is idempotent when repeated runs **reconcile actual state** rather than simply ignoring existing files. The default behavior should be:

| Existing state | Action |
|---|---|
| Not installed | Install, then verify |
| Already correct | Verify and report no change |
| Older managed version | Download, authenticate, stage, upgrade, verify |
| Newer managed version | Preserve unless downgrade explicitly authorized |
| Existing unmanaged config or conflicting symlink | Refuse overwrite and explain the conflict |
| Existing identical APT source/key | Do not duplicate or rewrite |
| Existing service, no relevant change | Do not restart needlessly |
| Partially failed prior run | Recheck actual state, safely resume applicable steps |

**Failure handling is not universal rollback.** A verified, staged single-file replacement can often leave the old file untouched until final rename, and it may be restorable if the prior version was retained. `apt-get install` can execute root-level maintainer scripts, alter dependencies and leave a partially configured package. Do not promise to undo those side effects automatically.

Retry a temporary download failure a bounded number of times. Do **not** retry a wrong signing key, wrong hash, unsupported distribution, malformed archive or permission denial until the cause changes. Every fatal error should produce nonzero exit and an actionable message. Cleanup must not replace the original failure with a false success.

## 8. Common mistakes found in real installers

- **Missing verification is treated as optional.** The supplied dtop hash helper can skip verification if a hashing tool is absent; a strict installer must fail instead.
- **Co-hosted hashes are overtrusted.** The Dux and chroncal examples fetch SHA-256 alongside the artifact; good for detecting mismatches, not equivalent to a separately trusted signature.
- **Archive extraction is too trusting.** Extracting a tarball directly into the final binary directory or inspecting only the expected executable afterward is insufficient.
- **Temporary filenames are predictable.** Starship's fallback when `mktemp` is absent is unsuitable as a secure default.
- **Downloads flow straight into privileged files.** Some APT snippets write keys/sources directly, or pipe into `sudo tee`; this creates partial-write and error-propagation risks.
- **Old APT trust is copied forward.** A legacy Tailscale branch uses `apt-key`; do not adopt it for new modern Debian/Ubuntu installers.
- **Profile files are edited broadly.** A tool may need to be added to PATH, but touching every user shell startup file is intrusive; print exact instructions or make a narrow edit opt-in.
- **A successful copy is called a successful install.** Check the installed executable's actual version, dpkg state and/or service readiness.

These are *specific weaknesses in the supplied snapshots*, not judgments about the overall projects or their current upstream versions.

## 9. Implementation checklist

- [ ] Declare exact Linux distributions/releases, architectures and ABI support; reject all others safely.
- [ ] Choose POSIX `sh` or Bash intentionally; validate shebang and external utility flags.
- [ ] Identify authoritative artifacts/repositories and independently trusted digest/signature/key.
- [ ] Define local/system scope, privilege operations and unattended/TTY rules.
- [ ] Use private temporary workspace, checked HTTPS transfer and mandatory verification.
- [ ] Validate archive members, paths, owners, symlinks and destination conflicts.
- [ ] Stage changes safely; preserve existing unmanaged configuration.
- [ ] Keep APT source/key scoped, deduplicated and verified before package installation.
- [ ] Apply PATH and systemd changes only under documented consent/policy.
- [ ] Verify the installed target; return nonzero if validation fails.
- [ ] Describe rollback limits and a safe re-run/recovery procedure.

## 10. Testing checklist

Do not test a destructive installer on your daily-driver host. Use mock commands, isolated temporary directories, disposable Debian/Ubuntu containers and systemd-enabled VMs as applicable.

- [ ] **Static:** `sh -n`/`dash -n` or `bash -n`; ShellCheck; review quoting, pipelines, traps, privilege escalation and unsafe `|| true`.
- [ ] **Functional:** clean install; re-run; correct version; upgrade; downgrade denial; unsupported OS/arch; missing tools; readonly destination; conflicting files and symlinks.
- [ ] **Network and supply chain:** DNS failure, timeout, 404, transient 503, partial transfer, wrong digest, wrong signing key, malformed archive and dangerous members.
- [ ] **APT:** exact suite/architecture, duplicate/conflicting repository, signature failure, APT lock, package script failure and installed version.
- [ ] **Service:** absent systemd manager, inactive policy, authorized enable/start, no-op restart avoidance, failed startup/readiness.
- [ ] **Recovery/UX:** SIGINT/SIGTERM, interrupted install then re-run, path with whitespace, noninteractive `curl | sh`, no sudo and command shadowing.

Record what was **actually executed** and its result. Never call static review a runtime test. The companion blueprint provides a test matrix with stable IDs such as `TEST-SEC-01`, `TEST-APT-03`, and `TEST-SVC-06`.

## 11. Using the technical blueprint with a coding agent

Provide the agent the blueprint, the **project-specific facts**, and the chosen installer category. Require it to identify applicable `PAT-*` patterns, `REQ-*` requirements and `TEST-*` cases, rather than cloning all reference scripts. It should produce a concise engineering plan first, implement the installer, and then provide actual test results and known limitations.

A compact reusable instruction:

> Implement a production-quality Linux installer following `INSTALLATION_SCRIPT_ENGINEERING_BLUEPRINT.md`. Use the smallest appropriate shell and installer category. Before coding, establish the exact supported OS/ABI matrix, authoritative artifact origin, independently trusted verification method, install scope, managed files and optional service actions. Implement detection, verified acquisition, safe staging, state-aware commits, cleanup, explicit failure handling and final verification. Test the applicable `TEST-*` scenarios. Never invent repository metadata, disable verification, overwrite unmanaged state or claim unexecuted tests passed.

**Reference provenance:** This guide and blueprint are based on the nine user-provided files `tailscale.sh`, `rust.sh`, `startship.sh`, `dtop-install-script.sh`, `chroncal-install-script.sh`, `dux.sh`, `ghostty.sh`, `docker-apt-repo.md`, and `mullvad.sh`. The references were **reviewed statically**, not executed; the Docker/Mullvad materials are fragments. The technical blueprint contains the full inventory, line-level evidence, detailed primitives, scenario blueprints, decision tables and verification matrix.
