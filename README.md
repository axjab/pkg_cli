# pkg — build locally, publish over SSH

`pkg` manages staged Debian packages in `.pkg/packages/`, builds local archives,
and publishes them to a configured signed APT repository. Runtime code is Bash
with standard Debian command-line tools. Gum supplies interactive selection.

Compile the checkout with `do/compile` to install `/exe/pkg`. Ensure `/exe` is on
PATH. The compiled command runs independently of the checkout.

## Command schema

```bash
pkg version                         # 0.0.0 for now
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
pkg build myapp
pkg host add apt@server
pkg host                            # configured hosts
pkg ping apt@server
pkg push myapp to apt@server
```

Package arguments may be omitted when the target is unambiguous. With multiple
matches, terminal input prompts for a choice; noninteractive input fails with
explicit-selection guidance. No mutation occurs before the ambiguity is resolved.
For automation, specify the category, package, and a package-relative path where
basenames collide. Input is never evaluated as shell code.

`pkg new` creates every skeleton directory, including empty categories.
`create`, `hosts`, `--dep`, `--deps`, and `--executables` remain compatibility aliases.

## Components

```bash
pkg add [<category>] <source-or-dependency> [as <path>] [to <package>]
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
Existing different files are never overwritten. Stage directory contents as
individual files; directory imports are not supported.

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

## Inspection

`pkg ls <package>` shows metadata once under `DEBIAN/control`, dependency
relationships separately, and color-coded components. Documentation, desktop
assets, and other are hidden when they have no files or symlinks. All remaining
categories remain visible. Every category uses a matching secondary entry color.
Redirected output is plain. `NO_COLOR=1` also disables color and selects plain
interactive prompts; otherwise interactive selection uses Gum.

## Build and publication

`pkg build` writes to workspace `dist/`. Increment the package version before
building changed contents when that output filename already exists.
`pkg push` publishes an existing built archive to the selected host, creates
repository directories and signing boilerplate, generates and verifies signed
APT metadata, and activates the publication. An omitted host uses the only
configured host or prompts. The target account home is the repository root;
HTTPS serving is configured separately. `localhost` publishes locally.

Build/install the CLI itself:

```bash
do/build-deb
sudo apt install ./dist/pkg-cli_0.1.0_all.deb
```

The Debian package declares `gum` and `openssh-client` dependencies. Its package
version comes from `packaging/pkg-cli.control`; the CLI's `version` subcommand
currently reports the requested hardcoded `0.0.0` independently.

Client repository bootstrap (configures trust/source, without installing packages):

```bash
curl -fsS https://apt.alj.cx/install | sh
```

## Verification and updates

Run `do/test-schema` for Bash regression tests of the compiled CLI: metadata,
all component categories, package renaming/removal, noninteractive ambiguity,
terminal prompts, path safety, inspection colors, and a real package build.
The older `do/test` remains the legacy test-suite entry point.

Updates are ZIP overlays with checkout-relative paths. Extract over the checkout,
run `do/compile`, then test in a disposable package workspace.
