# pkg_cli handoff

## TLDR

Local package creation, staging, and building work. Host registration and SSH reachability checks are implemented and approved, including helpful output when no hosts exist and green/red test results.

**Next: discuss and implement a standalone remote repository preflight.** The `.deb` publication validator is deferred; its issue text was drafted, but no GitHub issue was created.

**Do not implement `pkg push` yet.** First build and verify the entire publication pipeline as independent scripts.

## Working agreement

- Keep changes small. Test each checkpoint and let the maintainer verify before advancing.
- Use the current checkout as authoritative; attachments are snapshots.
- Keep answers short and concrete. Explain needs in plain English before proposing commands.
- Resolve ambiguity interactively in a terminal; require explicit arguments when running noninteractively.
- Prefer natural command words; avoid new double-dash options. Existing `--debug` remains.
- Defer documentation and repository cleanup.
- Notify the maintainer when the session reaches a useful handoff point.
- Use direct `curl` requests to GitHub’s API, never `gh`.

## Accepted model

- `pkg build` is **local by default**.
- `pkg push` will publish an already-built local package to a remote host.
- Follow Docker’s distinction between local artifacts and remote publication.
- Use SSH/rsync target syntax, accepting aliases and `user@host`.
- Use direct filesystem operations for `localhost`.
- Keep future remote operations possible without implementing remote builds now.

Example SSH configuration:

```sshconfig
Host pkg-host
    HostName old_shrine
    User apt
```

Both `pkg-host` and `apt@old_shrine` are valid targets.

## Current implementation

### Local commands

- `pkg init`: initialize or preserve a workspace.
- `pkg ls`: list sorted package names.
- `pkg create <name>`: create an empty package; reject duplicates.
- `pkg add`: stage files into an existing package.
- `pkg build [package] [to <directory>]`: build a `.deb`, defaulting to workspace `dist/`, and print its absolute path.

Package selection automatically chooses the sole package. Ambiguous selection prompts in a terminal and fails noninteractively without an explicit choice.

Workspace discovery walks upward to the nearest valid `.pkg`. A malformed marker stops discovery. Operations preserve the caller’s working directory.

### Host checkpoint — approved

```bash
pkg host add pkg-host
pkg host
pkg hosts
pkg ping pkg-host
pkg ping
```

- Hosts are registered offline in the nearest workspace’s `.pkg/hosts`.
- `pkg host` and `pkg hosts` list registered hosts.
- An empty list prints guidance to stderr, leaves stdout empty, and exits successfully:

  ```text
  No hosts configured. Add one with pkg host add <host>.
  ```

- An explicit `pkg ping <host>` works outside a workspace.
- With no target, `pkg ping` selects the sole host or prompts on ambiguity.
- SSH failures preserve the SSH exit status.
- Successful checks are green; failures are red.
- Redirected output is plain; `NO_COLOR=1` disables color.

Relevant files:

```text
lib/hosts.sh
lib/pkg-host
lib/pkg-hosts
lib/pkg-ping
tests/test_pkg_hosts.py
```

## Verification

The latest checkpoint passed **45 tests**, including standalone handlers and the compiled CLI.

Verified behavior includes:

- Empty host-list guidance.
- Host registration and selection.
- Successful mocked SSH checks.
- Actual SSH hostname-resolution failure with exit status `255`.
- Localhost execution.
- Color and `NO_COLOR` behavior.

Run:

```bash
python3 -m unittest discover -s tests -v
```

`compile` takes no arguments, bundles the current directory’s `lib/`, and writes `/exe/pkg` with mode `0755`. Compiled tests previously used a temporary `/exe` bind mount and `PKG_TEST_BINARY`.

## Publication goal

`pkg` should hide repository boilerplate and produce this structure:

```text
apt/
├── apt-signing-key.asc
├── dists/
│   └── trixie/
│       ├── InRelease
│       ├── Release
│       └── main/
│           └── binary-amd64/
│               ├── Packages
│               └── Packages.gz
└── pool/
    └── main/
        ├── axjab-hello_0.0.0_all.deb
        └── core_0.0.0_all.deb
```

Proposed eventual interface, still subject to confirmation:

```bash
pkg push [package...] [to <host>]
```

The old publication setup used `~/public/apt`, distribution `trixie`, and component `main`. **Do not assume the old repository path or signing identity is accepted for the new host.**

## Deferred work

### Explicit workspace selection

An issue draft exists for:

```bash
pkg -C <directory> <command>
```

This remains deferred, including the decision about relative path resolution.

### Standalone `.deb` publication validator

The maintainer explicitly asked to skip implementation and record an issue instead.

Issue title:

```text
Add a standalone .deb publication validator
```

Acceptance criteria:

- Accept an archive produced by `pkg build`.
- Verify metadata and payload are readable.
- Report package name, version, architecture, and SHA-256.
- Fail clearly with a nonzero status for missing, malformed, or truncated archives.
- Test valid and truncated archives.

**Only Markdown issue text was provided. No issue was posted:** no GitHub token or issue-creation connection was available.

The latest issue-script target is `axjab/pkg_cli`; an earlier repository reference was `axjab/packages`.

## Next checkpoint

Discuss the interface and scope of a **standalone remote repository preflight**, then implement and test only that checkpoint.

It should establish whether the selected SSH account can access the intended repository location and perform the required signing work. Confirm the repository location and signing expectations before implementing those assumptions.

Keep checks distinct from provisioning or publication.

## Remaining TODO

- [ ] Agree on remote repository preflight behavior.
- [ ] Implement and test its standalone script.
- [ ] Build standalone archive transfer/staging.
- [ ] Generate repository indexes and Release metadata.
- [ ] Sign and verify repository metadata.
- [ ] Publish safely, preserving the existing repository on failure.
- [ ] Verify installation from a clean Debian environment.
- [ ] Only after the standalone pipeline is verified, integrate `pkg push`.

## Files and environment

Latest implementation snapshot:

[pkg-publish-ssh-step.zip](https://chatgpt.com/library?file_id=libfile_678828fec7c08191921a9627c3250c01&account_id=personal)

Reusable interactive issue script using direct `curl`:

[github-issue.sh](https://chatgpt.com/library?file_id=libfile_c544eac4a1dc81919c46a55cab9d5912&account_id=personal)

Existing roadmap:

[PKG-REFACTOR-ROADMAP.md](https://chatgpt.com/library?file_id=libfile_6c3303c264b48191ae6b8d25cac4221f&account_id=personal)

Previous work used `/workspace/scratch/e10931fce349/pkg_cli`. Check whether it still exists before relying on it. No live maintainer checkout was mounted; request or inspect the current checkout before treating the snapshot as authoritative.
