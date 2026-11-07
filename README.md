# Step 1: workspace initialization

Copy `lib/pkg-init`, `lib/pkg-ls`, and `lib/workspace.sh` into your checkout's
`lib/` directory, after backing up the current `lib/pkg-init`. Keep your current
dispatcher. It must pass the caller's working directory unchanged to handlers.
Only `pkg-init` and `pkg-ls` are executable; `workspace.sh` is a sourced helper.

Internal layout: `.pkg/packages/<package-name>/`. The directory starts empty.
Package creation and control-file handling are deferred. No existing `deb/`
packages are migrated, and no add/build/push scripts change in this step.
Do not use those old commands as part of the new workspace workflow yet.

`pkg init` takes no operands for now. It reuses the nearest ancestor workspace,
or initializes the current directory if none exists. Repeat initialization
preserves contents and restores a missing empty `packages/` directory.
`pkg ls` prints sorted package names, one per line. It searches physical parent
directories; an invalid marker stops discovery. Marker/storage symlinks are
rejected in this first version. No registry or Git repository is created.

With the updated `compile-pkg`, rebuild and run `./pkg --debug ls` or
`./pkg --debug init`. Debug lines go to stderr and show the directories
checked, the selected workspace, and the listing or initialization result.
Set `NO_COLOR=1` for plain text logs you can compare across runs. When
running a handler directly, set `PKG_DEBUG=1` to enable the same diagnostics.

## Manual gate

Set `pkg_cli` to the absolute path of your existing launcher, then:

```bash
pkg_cli="$HOME/src/packages/pkg"
trial=$(mktemp -d)
cd "$trial"
"$pkg_cli" ls          # error; exit 1
"$pkg_cli" init        # initialized; exit 0
"$pkg_cli" ls          # no output; exit 0
"$pkg_cli" init        # reinitialized; exit 0
mkdir child
cd child
"$pkg_cli" ls          # no output; exit 0
"$pkg_cli" init        # reuses parent; creates no child/.pkg
```

Run `bash tests.sh` from this extracted directory for isolated automated checks.
Those checks use internal fixtures solely to verify listing and preservation;
operators will create packages through a later CLI command.

Status: implementation candidate. Await the maintainer's launcher-level test
before proceeding to package creation or another refactor.

Rollback: restore the backed-up `lib/pkg-init`; remove the two newly added files.
Use a disposable workspace for this test. Keep all existing package data.
