
# Draft: new syntax to counter ambiguity and support multiple items

## Future of pkgcli

Should `pkgcli` be CLI-only or allow packages as YAML too?

Simulation:

Mimic docker command, where deb archive is the target image

```bash
# write core.pkg (YAML) or Pkgfile
pkg build  # resolves to .pkg file OR Pkgfile
pkg push

# on change -> trigger Github Actions or git hooks -> same commands, no need for pkg add probably
```

## Metadata

```bash
pkg edit <package>
```

or interactively

```bash
pkg iedit <package>  # or simply supply -i
```
**Notes and features**:
- *feat*: Version is preferrably incremented automatically
- *feat*: Priority needs choice list, new issue
- *feat*: Maintainer should be sourced from external config
- *feat*: Architecture must default to current OS arch
- *feat*: Explore FULL package definitions as YAML files? Does that mke the CLI obsolete? To discuss...
- Dependencies are preferably handled with `pkg add dep:`

## Members

Categories are flagged with either `category:` or traditional `--category`

```bash
pkg add \          #
    dep: d1 d2 \   # declares d1 and d2 as dependencies in DEBIAN/control
    bin: b1 b2 \   # adds executables b1 and b2 to bin/
    etc: c1 c2 \   # adds config files c1 and c2 to etc/
    hook: h1 h2 \  # adds lifecycle scripts
    svc: s1 s2 \   # adds service files s1 and s2 to system/
```

### Provisional

For arbitrary files. Perhaps use a core.pkg.yml?

```bash
pkg bind \
  path/one:path/one \
  path/two:path/two \
  another/path/elsewhere:path/three
```
