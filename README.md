# pkg — build locally, publish over SSH

```bash
curl -fsS https://apt.alj.cx/install | sh
```

**pkg turns local executables into Debian packages and aims to publish them to a signed APT repository with one command.** The goal is to find and install those packages by name on a fresh Debian system after configuring its APT source and signing key.

Local package creation, staging, building, host registration, and SSH checks are implemented. **The next development work is `pkg push`, delivered in small, testable ZIP updates.** Preflight checks belong inside `pkg push`; you should not have to run a separate publication toolkit.

## Everyday workflow

Run `bash compile` in the `pkg_cli` checkout to install the bundled command at `/exe/pkg`. Ensure `/exe` is on your PATH. The installed command works independently of the checkout.

In a package workspace:

```bash
pkg init
pkg create hello
pkg add ./bin/hello to hello
pkg build hello
pkg host add pkg-host
pkg hosts
pkg ping pkg-host
```

`./bin/hello` must already be a readable executable. `pkg create` supplies placeholder control metadata. `pkg build` prints the resulting archive path, normally under the workspace's `dist/`.

Package arguments can be omitted when there is only one package. Where selection is ambiguous, the CLI prompts in a terminal; scripts must provide an explicit choice. Workspace discovery works from child directories too.

Useful commands:

```bash
pkg ls
pkg help
pkg help build
pkg --debug build hello
NO_COLOR=1 pkg --debug ping pkg-host
```

## Publication model

Builds remain local. Publication sends an existing local archive to the selected SSH account. SSH aliases and `user@host` targets are supported:

```sshconfig
Host pkg-host
    HostName old_shrine
    User apt
```

Both `pkg-host` and `apt@old_shrine` identify the intended destination. The target account's home directory **is the APT repository root**. It will be served over HTTPS by infrastructure managed separately. pkg does not configure HTTPS.

The intended interface being implemented is:

```bash
pkg push hello to pkg-host
pkg push hello    # infer the sole configured host, otherwise prompt
pkg push          # infer unambiguous package and host choices
```

These are development targets, not a claim that publication already works. The first checkpoint may only select inputs and run integrated readiness checks; it must clearly report that nothing has been published yet.

The finished command will transfer the selected archive, generate APT indexes and Release metadata, sign and verify InRelease, and activate the publication. It will manage `pool/`, `dists/trixie/`, and `apt-signing-key.asc` directly beneath the target home. `Architecture: all` packages must be discoverable by the intended amd64 Debian client.

## How we develop and test

1. The agent implements one useful increment inside `pkg push` and tests it.
2. The agent delivers a ZIP with complete replacement files at checkout-relative paths, such as `lib/pkg-push` and `tests/test_pkg_push.py`.
3. You extract it over your existing `pkg_cli` checkout, preserving unrelated files and package data.
4. You run `bash compile`, then the short manual test supplied with the checkpoint.
5. You send the actual output back. The agent fixes failures before advancing.

No repeated redesign of settled decisions, no prerequisite standalone-script detour, and no full pipeline delivered before you can test the first useful step.

## Status and scope

The previous host checkpoint reported 45 passing tests, including handler and bundled-CLI coverage. A standalone `publish-preflight` prototype exists as implementation reference; its presence does not prove the new host is ready or that `pkg push` is implemented.

Explicit workspace selection (`pkg -C`) and a separate archive-validator command are deferred. Necessary input checks remain part of push. Legacy migration, project registries, remote builds, installers, and repository cleanup are later work.

See **PKG-CLI-HANDOFF.md** for the complete implementation contract, checkpoint plan, testing expectations, source references, and superseded decisions.
