# Unified pkg interface

Use packages/ for package sources so pkg can be the root command.

| Path | Contents |
| --- | --- |
| pkg | Public dispatcher |
| libexec/pkg-* | init, add, build, push and help implementations |
| packages/ | Existing package source directories |
| dist/ | Built archives |
| scripts/ | install-core.sh, install.sh, pkg-tutorial, publish and start-os |
| docs/ | PACKAGE-TEST-PLAYBOOK.md, STATUS.md and this guide |
| README.md | Repository introduction |
| reference/ | Existing reference material |

## Apply to the existing checkout

Run from ~/src/packages before extracting the archive. This assumes the existing pkg entry is the package source directory.

```bash
test -d pkg && test ! -e packages && mv -- pkg packages
mkdir -p libexec scripts docs
mv -- pkg-init pkg-add pkg-build pkg-push libexec/
mv -- install-core.sh install.sh pkg-tutorial publish start-os scripts/
mv -- PACKAGE-TEST-PLAYBOOK.md STATUS.md docs/
unzip /path/to/pkg-interface.zip -d .
chmod +x pkg libexec/pkg-*
./pkg help
```

The archive contains the dispatcher, updated subcommands and this guide. Extraction replaces the four old subcommands moved into libexec/. Review or commit existing changes before applying it.

Only the four attached scripts were available for updating. Supporting scripts moved into scripts/ may still refer to the old layout. Update their relative paths before using them. In particular, the earlier pkg-tutorial expects pkg/core and root-level pkg-* commands. The supplied pkg-push is unfinished and now fails explicitly instead of silently succeeding.

## Use

```bash
./pkg help
./pkg help add
./pkg init core
./pkg add /path/to/tty-notify core
./pkg build core
```

The dispatcher preserves the calling directory and forwards arguments exactly. Commands find packages/ and dist/ relative to their own checkout. An executable libexec/pkg-example is automatically available as pkg example. Help explains the currently implemented behavior and remaining limitations.

A symlink to the root pkg file can be installed in ~/.local/bin to invoke pkg from anywhere. The dispatcher resolves that symlink before finding libexec/.

Verified in a disposable checkout with actual init, add and dpkg-deb build operations, including a source path containing spaces. Also verified generic subcommand discovery, argument forwarding, exit status propagation, invalid subcommand rejection and invocation through a symlink.
