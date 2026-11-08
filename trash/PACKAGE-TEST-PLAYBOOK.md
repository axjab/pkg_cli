# Debian package workflow and test playbook

Keep package sources in `~/src/packages`, publish built archives through the APT repository on `majula`, and install by name on Debian 13 amd64. `core` is the first package for desktop and headless machines.

## Authoring workflow

| Command | Contract | Current entry point |
| --- | --- | --- |
| `pkg init core` | Scaffold a package directory with `DEBIAN/control`, `bin/` and a README covering edit, build, publish and install. Track the metadata, payload and instructions in Git. Use the existing parent repo when present. | `./pkg-init core` scaffolds the package. README generation and Git setup are target behavior. |
| `pkg add ./tty-notify` | Add an executable to the current package with mode 0755. | `./pkg-add ./tty-notify core` |
| `pkg add --depends network-manager` | Add an APT package name to `Depends` in `DEBIAN/control`. APT resolves and installs it from the machine’s configured sources. | Proposed syntax. Edit `Depends` directly until supported. |
| `pkg build` | Build the selected package as a `.deb` in `dist/`. | `./pkg-build core` |
| `pkg push` | Upload the exact archive for the selected package and version, rebuild the index, generate `Release`, then sign and verify `InRelease`. Return failure if any step fails. | Target entry point `./pkg-push core`. The handoff records a manual publication of `core`. |

Use the package directory as the default target for the eventual `pkg` command. From the repo root, supply an explicit package name when the command needs a target. Keep generated `dist/` artifacts out of Git. Increment the Debian version before publishing changed contents.

For a third-party `.deb`, make its package available through an APT source first, then declare the dependency by its package name. Keep its files in its own package.

## Install by name

Once `install-core.sh` is hosted at the intended URL, run this once per machine with `curl` and CA certificates available. In a root shell, use `sh` in place of `sudo sh`.

```sh
curl -fsSL https://fs.alj.cx/sh/install-core.sh | sudo sh
```

The installer creates `/etc/apt/sources.list.d/alj.sources` with the ALJ public key embedded in `Signed-By`. It refreshes APT and installs `core`. Subsequent installs use the usual commands.

```sh
sudo apt update
sudo apt install core
```

The proposed installer URL returned HTTP 404 when checked. Before hosting it, run the downloaded `install-core.sh` locally with `sudo sh ./install-core.sh`.

## Interactive tutorial

Keep `pkg-tutorial` and `install-core.sh` in the same directory. Launch the REPL with Bash and point it at your package checkout.

```sh
bash ./pkg-tutorial ~/src/packages
```

Use `show` for the current instructions, `shell` to open a Bash session in the checkout, and `check` to verify the result. Type `exit` to return from Bash, `next` or `back` to move between stages, and `quit` to end the tutorial. The publish check compares the local archive with the public copy. The install check runs APT in a disposable Docker container.

## Release checks

Run authoring checks from `~/src/packages`. Use a disposable checkout and a staging remote for intentional failures.

| Stage | Test | Pass condition |
| --- | --- | --- |
| Init | Initialize a new package in a disposable checkout. Run `git status --short` and inspect the scaffold. | Control file, payload directory and usage instructions exist. Source files are trackable in the intended Git repo. Reinitializing preserves existing files. |
| Add executable | Add a test executable. Inspect the staged file and try adding a missing path. | The file is executable. An invalid path fails without changing the package. |
| Add dependency | Add `network-manager` twice, then build and read the archive's `Depends`. | The field contains one `network-manager` entry. A clean APT install pulls in the dependency and exposes `nmcli`. Run this check when adding the dependency. |
| Build | Run `./pkg-build core`, then inspect the archive with the commands below. Repeat on a fixture with invalid control metadata. | Package, version, architecture and executable mode match the source. The invalid fixture fails the build. |
| Push | Run `./pkg-push core` against staging with a second package artifact also in `dist/`. Test a missing artifact and a signing failure separately. | Only the selected artifact uploads. Its entry appears in `Packages`, the server verifies `InRelease`, and a fresh client fetches both the index and archive. Each failure returns nonzero. Check staging repository health after a failed push. |
| Upgrade | Install the prior release, publish a higher version, then run `apt-get update` and `apt-get install --only-upgrade -y core`. | `dpkg-query -s core` reports the new version and the new payload works. |

### Inspect and install the build locally

Replace `VERSION` with the value in `pkg/core/DEBIAN/control`.

```sh
./pkg-build core
deb=dist/core_VERSION_all.deb
dpkg-deb -f "$deb" Package Version Architecture Depends
dpkg-deb -c "$deb"
```

Mount `dist/` read-only at `/pkg` in a disposable Debian 13 container. Run `apt-get update` against its configured sources if the build declares dependencies, then run `apt-get install -y /pkg/core_VERSION_all.deb`. Check `dpkg -L core` and `command -v tty-notify`. This isolates package contents from publication.

### Install from the live repository

Start a second fresh container without a `.deb` mount. From the directory containing `install-core.sh`, run:

```sh
docker run --rm -it --platform linux/amd64 \
  --mount "type=bind,source=$PWD/install-core.sh,target=/tmp/install-core.sh,readonly" \
  debian:trixie-slim sh
```

Inside the container:

```sh
set -e
apt-get update
apt-get install -y ca-certificates
sh /tmp/install-core.sh
apt-cache policy core
dpkg-query -s core
command -v tty-notify

# Verify that a normal install fetches the archive again.
apt-get purge -y core
apt-get clean
apt install -y core
dpkg-query -s core | grep -Fx 'Status: install ok installed'
command -v tty-notify
```

`apt-cache policy core` should list `https://fs.alj.cx/apt` for the expected version, and `tty-notify` should resolve to `/usr/bin/tty-notify`. Rerun the bootstrap once to check it reuses the same source entry. Once the script is hosted, repeat the test in a new container using `curl` in place of the bind-mounted script. Install `curl` alongside `ca-certificates` first.

## If a check fails

| Symptom | Check |
| --- | --- |
| `Unable to locate package core` | Confirm the ALJ source exists, `apt-get update` succeeds and `apt-cache policy core` shows an ALJ candidate. |
| Signature or key error | Check that the signed index uses the expected ALJ key fingerprint, `C3E0EAB9CF5B9E6C1D9CDD2FF3740ED5AEB3E0FD`. |
| Hash mismatch or missing archive | Compare the published index against the uploaded archive. Check that publication ran in upload → index → release → signing order. |
| New build has the same version | Bump `Version`, rebuild and publish before rerunning the upgrade test. |

## References

[APT sources and Signed-By](https://manpages.debian.org/trixie/apt/sources.list.5.en.html) · [APT archive authentication](https://manpages.debian.org/trixie/apt/apt-secure.8.en.html) · [Debian package dependencies](https://www.debian.org/doc/debian-policy/ch-relationships.html)
