# pkg_cli handoff

**TLDR for the maintainer.** We now have a portable `pkg` command that
finds workspaces, creates empty packages, and explains its decisions through
colored debug output. You verified the package structure. Next, agree on
how `pkg add` selects a package, then implement and test that one step.

## Working policies

### Design and collaboration

- The maintainer leads the design. Ask focused questions when an interface
  or behavior needs a decision. Label proposed syntax until it is accepted.
- Make one small change at a time. Test it and let the maintainer verify the
  checkpoint before advancing. Roll back and redesign a misdesigned step.
- Use Git as the guiding model for workflow and discovery, adapting it to
  this project's needs. Keep the implementation simple.
- Keep replies short, concrete, and in plain English. Prefer quality over
  quantity. Commit messages should explain the actual change plainly.
- Use the current checkout as authoritative. Older attachments and docs
  can describe superseded behavior. Docs and cleanup are deferred.

### CLI and workspace rules

- The command is `pkg`, exactly three characters. The repo is `pkg_cli`.
  The build helper is `compile`.
- Prefer natural-language command words and avoid new double-dash arguments.
  Use `pkg help` and `pkg help <command>`. The explicitly requested
  global `--debug` flag remains supported.
- Keep handlers under `lib/` as `pkg-<command>`. Source shared shell
  code such as `workspace.sh`.
- `compile` takes no arguments, bundles the current directory's entire
  `lib/`, and writes `/exe/pkg` with executable mode `0755`.
  The destination is deliberately hardcoded.
- Each initialized directory is a workspace containing several packages.
  Use one hidden directory, `.pkg/`, for managed metadata and internal
  package state. Operators choose names for other directories.
- Provide CLI access to everything operators need to inspect or change
  inside `.pkg/`. Future metadata editing must be available through the CLI.
- Workspace operations must work independently of the CLI checkout.
  Preserve the caller's working directory and find the nearest workspace.

### Code style and tests

Continue the style of the accepted implementation.

- Use readable Bash, descriptive names, clear validation, and brief comments
  explaining intent. Current handlers use `#!/usr/bin/env bash` and
  `set -euo pipefail`.
- Quote paths and argument expansions. Forward arguments with `"$@"`.
  Support spaces in paths and preserve meaningful exit statuses.
- Reuse the shared workspace resolver and debug helper. Keep abstractions
  small and useful. Avoid unnecessary configuration and indirection.
- Preserve existing data on failure and duplicate names. Stage multi-file
  changes before publishing them. Clean up temporary state and check
  concurrent duplicate attempts where applicable.
- Include unit tests with new command behavior. The accepted suite uses
  Python's standard-library `unittest` to invoke Bash handlers. Cover
  successful behavior and meaningful failure cases.
- Also test the compiled command through its normal CLI entry point,
  including stdout, stderr, exit status, discovery, and debug behavior.

### Debugging requirements

- Expose actual decisions and runtime state inside the command. Log values
  from the code performing the operation.
- Show current-directory marker presence, each path searched, discovery
  success, and the selected root. Show package names and counts for listing,
  and targets and outcomes for mutations.
- Emit context before the main operation and results as they become known.
  Keep field names and ordering stable for regression comparisons.
- Colorize diagnostics. Current output uses cyan labels, green `true`,
  and red `false`. Honor `NO_COLOR=1`.
- Write diagnostics to stderr so stdout remains usable by other commands.
  Focus on package and workspace behavior. The maintainer explicitly
  rejected locale information and unrelated environment dumps.

## Current setup

- The repo is named `pkg_cli`. Its purpose is to develop the `pkg` CLI.
  The old package trees under `deb/` and archives under `dist/` are
  still useful as references.
- Run `bash compile` at the repo root to bundle executable handlers in
  `lib/` into `/exe/pkg` with mode `0755`. Help uses `pkg help`
  and `pkg help create`. Prefer readable command words over new
  double-dash flags. The existing global `--debug` flag is intentional.
- Workspace discovery starts at the current directory and walks upward.
  The nearest valid marker wins. A malformed marker stops discovery with
  an error. `pkg init` creates an empty workspace or preserves an
  existing one. `pkg ls` prints sorted package names, with empty output
  for an empty workspace and exit status 1 when discovery fails.
- `pkg create <name>` makes an empty package and rejects duplicates.
  The control template uses version `0.0.0`, architecture `all`,
  section `utils`, and priority `optional`. Maintainer and description
  are placeholders. Package files and metadata live under `.pkg/`.
- `pkg --debug <command>` writes colored diagnostics to stderr. It
  reports the paths checked, the selected workspace, and the operation
  result. Use `NO_COLOR=1` for plain logs. The maintainer verified
  discovery from the root, a child directory, and outside a workspace.
- All 13 creation tests passed, along with a smoke test of the bundled
  command. Run them with `python3 -m unittest discover -s tests -v`.

## Next task

Task 04b in the roadmap is package selection. Use the proposed
`pkg add ./bin/hello to hello` syntax as the starting point for the
decision. `create` makes a package. `add` stages a file in an existing
package. An unknown target should fail and point to `pkg create <name>`.
Confirm the selector before implementing the first workspace-aware
`pkg add` path. Start with staging one executable and verifying that it
lands in the named package only. `_tmp/lib.old/pkg-add` is the reference
for the previous behavior. Then continue toward build, legacy package
migration, and publication using the roadmap.

Use the maintainer's current checkout as the source of truth. Keep each
change small and test it before moving on. The maintainer deferred docs
and repository cleanup.

[PKG-REFACTOR-ROADMAP.md](https://chatgpt.com/library?file_id=libfile_6c3303c264b48191ae6b8d25cac4221f&account_id=personal)
· [pkg-create-step.zip](https://chatgpt.com/library?file_id=libfile_e05f634bc490819188c67f30e737e640&account_id=personal)
