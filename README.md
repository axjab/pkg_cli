# pkg — build locally, publish over SSH

`pkg` manages staged Debian packages in `.pkg/packages/`, builds local archives,
and publishes them to a configured signed APT repository. Runtime code is Bash
with standard Debian command-line tools. Gum supplies interactive selection.

Compile the checkout with `do/compile` to install `/exe/pkg`. Ensure `/exe` is on
PATH. The compiled command runs independently of the checkout.

## Command schema

```bash
pkg version                         # CLI version embedded at compile time
pkg help                            # or: pkg help <command>
pkg init
pkg new myapp
pkg add ./myapp to myapp
pkg add dependency 'gum (>= 2.0.2)' to myapp
pkg mv executable myapp to myapp-cli in myapp
pkg rm dependency gum from myapp
pkg ls                              # workspace package names
pkg ls myapp                        # categorized inspection
pkg set version 1.0.0 in myapp
pkg get version from myapp          # value only
pkg edit myapp                       # open DEBIAN/control
pkg build myapp
pkg host add apt@server
pkg host                            # configured hosts
pkg ping apt@server
pkg push myapp to apt@server
```

Package arguments may be omitted when the target is unambiguous. With multiple
matches, terminal input prompts for a choice; noninteractive input fails with
explicit-selection guidance. No mutation occurs before the ambiguity is resolved.
Package prompts use typed numbers. Enter accepts the last prompted choice, saved
per workspace and user in `.pkg/.last-package-<uid>`. Missing/deleted choices are
ignored. Explicit selections do not replace this remembered prompt default.
For automation, specify the category, package, and a package-relative path where
basenames collide. Input is never evaluated as shell code.

`pkg new` creates every skeleton directory, including empty categories.
`create`, `hosts`, `--dep`, `--deps`, and `--executables` remain compatibility aliases.

## Components

```bash
pkg add [-f] [<category>] <source> [as <path>] [to <package>]
pkg add dependency <name> [<version-or-constraint>] [to <package>]
pkg mv [<category>] <old> to <new> [in <package>]
pkg rm [<category>] <item> [from <package>]
pkg ls <category> [in <package>]
```

| Category | Default destination for added files |
| --- | --- |
| executable | `bin/<filename>` |
| configuration | `etc/<package>/<filename>` |
| service | `usr/lib/systemd/system/<filename>` |
| documentation | `usr/share/doc/<package>/<filename>` |
| asset | `usr/share/<package>/<filename>` |
| desktop | `usr/share/applications/` for `.desktop`, otherwise `usr/share/icons/` |
| metadata | `DEBIAN/<filename>` |
| lifecycle | `DEBIAN/<hook>`: preinst, postinst, prerm, postrm, config |
| other | Requires `as <package-relative-path>` |
| dependency | An entry in `Depends` |
| package | Use `new`, `mv package`, or `rm package` |

`config`, `exe`, `dep`, `doc`, `assets`, `dependencies`, and `executables` are
accepted aliases. Explicit destinations must belong to the selected category.
Source files are copied; executable and lifecycle files receive mode 755, other
files mode 644. Executable sources must already have execute permission.
Use `pkg add -f ./myapp to myapp` to replace a conflicting staged file.
Stage directory contents as individual files.

```bash
pkg add configuration ./myapp.conf to myapp
pkg add service ./myapp.service to myapp
pkg add asset ./template as usr/share/myapp/templates/default to myapp
pkg add lifecycle ./postinst to myapp
pkg add metadata ./conffiles to myapp
pkg ls service in myapp
pkg mv configuration etc/myapp/myapp.conf to defaults.conf in myapp
pkg rm service myapp.service from myapp
```

File paths and familiar suffixes inform inference. A bare word that could name
both a dependency and a local file prompts; `./file` or an explicit category
resolves this. Unknown file types require a category in scripts. Configuration
files are staged as supplied; add `DEBIAN/conffiles` explicitly when needed.
Service files are staged; installing/enabling services requires suitable hooks.

Filtered queries print paths or dependency entries without headings or color;
empty categories produce empty output. Legacy `--executables` retains its old
`bin/` basename output. `pkg ls <package>` gives exact package names precedence
when a package has the same name as a category; use `in <package>` to query that
category explicitly.

`mv` accepts a basename to rename a file in place or a package-relative path to
relocate it. `rm` removes a staged file/symlink or a whole staged package when
selected as a package. Package deletion leaves built archives and published
versions alone. `DEBIAN/control` is protected; use metadata commands to edit it.

## Metadata and dependencies

```bash
pkg set description 'My terminal utility' in myapp
pkg set Maintainer 'Me <me@example.com>' in myapp
pkg set X-Owner 'operations' in myapp
pkg get X-Owner from myapp
pkg set Description $'Short summary\nLong description' in myapp
pkg mv dependency gum to 'gum (>= 2.0.2)' in myapp
pkg add dependency gum 2.0.2 to myapp       # gum (>= 2.0.2)
pkg add dependency curl '= 8.0' to myapp    # curl (= 8.0)
pkg mv package myapp to terminal-tools
pkg set name my-tools in terminal-tools
```

Fields are case-insensitive. `name` aliases `Package`; both `set name` and
`mv package` update the staged directory and control Package field together.
Payload paths and file contents are retained, so references inside scripts
remain under your control. Metadata updates validate a candidate control file
before replacing the original. Invalid changes leave the original intact.

Dependency commands accept one quoted relationship entry, including version
constraints and alternatives. A bare dependency name matches a versioned entry;
multiple matches prompt. Dependency `mv` replaces the entry atomically. Adding
an identical entry is idempotent; it does not silently replace a different
constraint for the same name. Repository origin is not encoded in Depends;
repository configuration and APT preferences remain client configuration.

The optional secondary version defaults to `>=`; quote a constraint to use `=`,
`<=`, `<<`, or `>>`. Versions are validated before changing Depends. With an
explicit `dependency` category, the second operand is always the version; use
`to <package>` for the target. `pkg add gum 2.0.2 to myapp` is also accepted.

`pkg edit [<package>]` opens the actual `DEBIAN/control` file, selecting a package
if omitted. It uses `VISUAL`, then `EDITOR`, then `editor`. Whitespace-separated
editor arguments are supported without shell evaluation; use a wrapper script
for complex quoting. A literal executable path containing spaces also works.
This is direct editing, so unlike `set`, it does not validate or normalize edits.

## Inspection

`pkg ls <package>` shows metadata once under `DEBIAN/control`, dependency
relationships separately in a terminal-width grid, and color-coded components.
Version constraints and alternatives stay together in one cell. Depends entries
appear directly under Dependencies; other relationship types retain labels.
Documentation, desktop
assets, and other are hidden when they have no files or symlinks. All remaining
categories remain visible. Every category uses a matching secondary entry color.
Redirected output is plain. `NO_COLOR=1` also disables color and selects plain
interactive prompts; category/target menus otherwise use Gum. Package menus
always use typed numbers.

## Build and publication

`pkg build` writes to workspace `dist/`. When rebuilding changed contents at
the same version, `pkg build -f myapp` replaces the existing archive after the
new build passes verification. You can also specify `to <directory>`.
`pkg push` publishes an existing built archive to the selected host, creates
repository directories and signing boilerplate, generates and verifies signed
APT metadata, and activates the publication. An omitted host uses the only
configured host or prompts. The target account home is the repository root;
HTTPS serving is configured separately. `localhost` publishes locally.
Use `pkg push -f myapp to apt@server` to replace a published archive with
the same package name, version, and architecture and regenerate signed indexes.

Build/install the CLI itself:

```bash
do/build-deb
sudo apt install ./dist/pkg-cli_0.1.1_all.deb
```

The Debian package declares `gum` and `openssh-client` dependencies. Its package
version and `pkg version` both come from `packaging/pkg-cli.control`. Run
`do/compile` after changing the version to update the standalone CLI.

Client repository bootstrap (configures trust/source, without installing packages):

```bash
curl -fsS https://apt.alj.cx/install | sh
```

## Verification and updates

Run `do/test-schema` for Bash regression tests of the compiled CLI: metadata,
all component categories, package renaming/removal, noninteractive ambiguity,
terminal prompts, path safety, inspection colors, and a real package build.
It also checks dependency versions/grids, direct editor invocation, persistent
numbered defaults, and copy-failure cleanup/status propagation.
The older `do/test` remains the legacy test-suite entry point.

The supplied legacy failure report mixes outdated assertions with regressions:

| Failure | Assessment |
| --- | --- |
| `create` guidance/help, old `Staged:` text, old add usage | Outdated wording/schema assertions |
| Bare filenames in build setup | Must use `./file` or `add executable` under ambiguity rules |
| Rejecting `in <package>` | Outdated: `in` is an accepted qualifier |
| Non-executable untyped source returning 2 | Intentional ambiguity error; explicit executable still rejects it |
| Symlink diagnostic wording | Rejection remains correct; assert no external mutation rather than old text |
| Traversal removal returning 1 instead of 2 | Still rejected; exact error-code expectation needs review |
| Empty `to ""` accepted | Real regression, fixed: exits 2 without mutation |
| Copy failure changed exit 7 to 1 | Real regression, fixed: propagates status and cleans staging |
| Missing staged/already-staged/failed debug events | Debug regression, restored |

Those older Python tests have not been migrated in this update, and `do/test`
is not claimed to pass. Their safety assertions remain important; current Bash
tests cover the new behavior and the real regressions listed above.

Updates are ZIP overlays with checkout-relative paths. Extract over the checkout,
run `do/compile`, then test in a disposable package workspace.
