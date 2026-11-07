# Package CLI refactor roadmap

**Status** — Planning. The maintainer leads the design. Agree on the next task and its test before changing code. Complete and verify one task at a time.

## Starting point

The current checkout uses `deb/` for package sources and `lib/` for command scripts. The maintainer verified that `./pkg init helloworld`, `./pkg add /exe/tty-notify`, and `./pkg build helloworld` produced a package whose executable was available after installing the local artifact in the test container. Record the exact artifact filename and current script behavior when capturing the baseline. Treat the latest checkout as authoritative.

The end state is an installed CLI available on `PATH`, with project discovery from the current directory or an explicitly selected directory, a list of remembered projects, and explicit access to SSH projects. Packages published to the signed APT repository should still be installable by package name. The roadmap keeps project selection and APT publication separate even when both involve SSH.

## Command name review

| Command | Long-term fit |
|---|---|
| `pkg` | Three keystrokes and familiar. FreeBSD and Termux already use it for package management, so putting this tool on PATH can shadow an existing command. The name also leaves the package format unspecified. |
| `deb` | As short and specific to the format, but shares its name with the existing `deb/` directory and reads like the artifact format. A separate installation path solves the filename collision. |
| `debwork` | Seven characters. Names the Debian package work and reads well as `debwork init`, `debwork build`, and `debwork push`. A targeted search found no obvious Debian packaging command with this name. Check the intended machines before installing it. |
| `debcraft`, `debpkg` | Both names are already used by Debian commands. |

Proposed shortlist — `debwork` with `.debwork/`, or `pkg` with `.pkg/` for a Debian-only environment where the maintainer accepts the generic name. `.deb/` is short and distinct from `deb/`, but the spelling also denotes the archive suffix. Matching the marker to the CLI makes it easier to remember. All names are provisional.

Name sources — [FreeBSD Handbook](https://docs.freebsd.org/en/books/handbook/ports/), [Termux pkg script](https://github.com/termux/termux-tools/blob/master/scripts/pkg.in), [Debian debcraft manual](https://manpages.debian.org/trixie/debcraft/debcraft.1.en.html), [Debian debpkg manual](https://manpages.debian.org/testing/devscripts/debpkg.1.en.html).

## Decisions to record

| ID | Decision | Status |
|---|---|---|
| D1 | Executable and marker directory names. Check the command on target systems before installation. | Open |
| D2 | One marker per package, or one marker for a workspace containing several packages. This determines whether ordinary commands infer the package or require a package selector. | Open |
| D3 | Marker contents and versioning. Decide what is tracked in Git, where the package payload and build output live, and whether `init` also runs `git init`. | Open |
| D4 | Discovery contract. Decide the starting directory, nested-project policy, symlink handling, mount boundaries, and the Git edge cases to support in the first release. | Open |
| D5 | Install and migration contract. Decide how the executable and command scripts are installed together, and how existing projects in `deb/` are adopted or moved. | Open |
| D6 | Registry contract. Decide which operations remember a project, where the list lives, whether aliases are supported, and how stale or moved paths are handled. | Open |
| D7 | SSH contract. Decide the target syntax, which host runs the command, and which host owns inputs and build outputs. | Open |
| D8 | Publish contract. Decide how `push` chooses the artifact and APT destination and how it handles retries and existing versions. | Open |

### Git behavior to pin down first

Proposed first contract — start in the current directory, walk upward to the nearest valid project marker, and fail clearly if there is no project. Commands that require no project, such as `help`, work from anywhere. A Git-style `-C <directory>` would explicitly select the starting directory. Define separately whether relative command operands follow that directory or the caller’s original directory.

In a temporary Git fixture, a child directory resolved to its parent repository, an initialized nested repository took precedence, an unrelated directory was rejected, and reinitializing preserved the existing Git configuration. Git also supports a `.git` pointer file and environment overrides. Decide which of those semantics are in scope before treating Git parity as an acceptance test. [Git command reference](https://git-scm.com/docs/git), [Git init](https://git-scm.com/docs/git-init), [Git repository layout](https://git-scm.com/docs/gitrepository-layout).

The project marker would establish project identity. The proposed per-user registry would store locations for convenience. Ordinary commands would resolve the current directory without consulting the registry, so a remembered project could never become an implicit fallback when discovery fails.

## Task list and test gates

Rows are proposed work units. The old checkout workflow remains the regression check during transition. Switch defaults in the cutover task after the project-aware routes pass.

| ID | Scope | Change | Test gate before the next task |
|---|---|---|---|
| 01 | Baseline | Capture the actual arguments, artifact name and path, exit codes, and current `push` behavior from the latest checkout. | Repeat the `helloworld` container test. Record which commands pass and which behavior is still pending. |
| 02 | `pkg`, `pkg-help` | Separate executable/script lookup from project lookup. Install the launcher and handlers together using a staging prefix first. Keep the checkout entry point during testing. | From outside the checkout, the installed command opens help and routes a test handler with arguments containing spaces and a nonzero exit status intact. An unknown command fails clearly. |
| 03 | `pkg-init` | Add an explicit project-mode initialization route with the approved marker and scaffold. Keep the old initialization route available for the transition. | Initialize an empty fixture. Re-run initialization with a sentinel file in place. Verify the agreed nested-init policy and clean failure on an invalid destination. |
| 04 | `pkg` | Add a single project resolver and a read-only way to test it. Validate the marker using the approved format. | Find the project at its root and from a child directory. Test the approved nested policy, invalid marker, unrelated directory, and symlink and mount rules. |
| 05 | `pkg-add` | Use the resolved project for the add destination. Preserve the verified executable-add behavior. | From a child directory, add a relative source path with spaces. Confirm the correct project receives an executable and a failed add leaves it intact. Check existing dependency-add behavior if present. |
| 06 | `pkg-build` | Use the resolved project for inputs and the approved output path. | Build from the root and a child directory. Inspect control metadata and payload, then install the resulting local `.deb` in a clean Debian container and run `tty-notify`. A failed build must leave no partial artifact presented as successful. |
| 07 | `pkg` | Add explicit path selection such as `-C`, using the same resolver. | From an unrelated directory, select each of two projects in turn. An invalid path fails without falling back. Verify relative operand semantics with `add`. |
| 08 | Migration | Define and test adoption of a legacy `deb/` project. Start with a copy and keep rollback steps reviewable. | Migrate a fixture with custom metadata and payload. Compare the previous and new package contents, then repeat the migration or exercise rollback according to the agreed behavior. |
| 09 | `pkg-push` | Use project resolution and explicit artifact selection. Test selection against a local fixture or fake publisher. | Correct artifact and destination selected from the intended project. Missing or ambiguous output fails before publishing. |
| 10 | `pkg-push` | Wire the selected artifact into the approved publish workflow in a staging APT repository. | Confirm signed metadata, install by package name from a clean Debian client, then upgrade to a newer version. Check retry and failed-upload behavior against staging. |
| 11 | CLI cutover | Switch to the agreed default syntax and install the final command. Align help, playbook, and interactive tutorial with the new workflow. | Run the installed command through init, add, build, and staging push from outside the CLI checkout. Exercise a migrated project and install by package name. |
| 12 | Registry | Store and list known local projects. Add the approved registration triggers and a way to adopt projects initialized elsewhere. | Verify deduplication, persistence across invocations, and the agreed behavior for stale and moved paths. Test concurrent writes before trusting the list. |
| 13 | Local registry selection | Allow an explicit registry entry to select the project without changing the caller’s shell directory. | Select either of two projects from elsewhere. Reject ambiguous names and stale entries with a clear error. Preserve normal directory discovery. |
| 14 | SSH target | Add an explicit remote target and start with a read-only discovery operation. | A test SSH host resolves the requested project. Cover paths with spaces, missing CLI, invalid marker, connection failure, and propagated remote status. |
| 15 | Remote registry and operations | Remember approved SSH targets and enable remote operations one command at a time. | Reuse a saved remote target, verify the host that reads inputs and writes output, and test each enabled operation independently. A failed SSH attempt must leave local projects untouched. |

For task 12, settle what “all projects” means. One proposal is to remember successful local initializations and migrations automatically, register existing projects on request, and defer any search of selected directories to an explicit scan command. Discovering arbitrary local or remote projects requires a defined search scope. Keep remote locations as host plus path so a remote directory and a local directory with the same spelling remain distinct.

Use `Ready`, `In progress`, `Verified`, or `Blocked` for each active task. Record the design decision, actual command and result, and any difference from the expected result before starting the next row.

| Task | Status | Decision or test result |
|---|---|---|
| 01 | Planned | Maintainer reported a passing manual smoke test. Capture the exact baseline from the latest checkout after the first design discussion. |

## First design discussion

1. Which public command and marker should we design around — `debwork` + `.debwork/`, `pkg` + `.pkg/`, or a different pair?
2. Does one initialized directory represent a single Debian package, or a workspace that can hold multiple packages?
3. Should the marker hold metadata only, with the package tree visible, or should it contain the package tree as well?
