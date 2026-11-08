# Status — Debian Packages and APT Publication

**Goal:** Automate publishing a locally built Debian pkg to the personal signed APT repository, then enable reliable installation on all trusted desktop and headless hosts.

## Confirmed working

- [x] `pkg-init <pkg>` — create pkg skeleton and `DEBIAN/control` placeholders.
- [x] `pkg-add <executable> [pkg]` — safely stage executables into `bin/`.
- [x] `pkg-build <pkg>` — build `.deb` and verify archive metadata, contents and extractability.
- [x] Stage `/exe/tty-notify` in shared pkg `core` (`Architecture: all`, initial version `0.0.0`).
- [x] Manually upload `core_0.0.0_all.deb` via `rsync` to `publish:public/apt/pool/main/`.
- [x] Manually regenerate `Packages` and `Packages.gz` using `dpkg-scanpackages`.
- [x] Manually regenerate `Release` using `apt-ftparchive`.
- [x] Sign `InRelease` using remote GPG in batch/no-TTY mode from the local PC.
- [x] Verify signature: `Good signature from "ALJ APT Repository"` (November 2, 2026).

## Open / not yet verified

- [ ] **End-to-end `apt install core` in fresh Debian 13.** Prior failure was `Unable to locate package core` because the personal APT source was not configured in the container.
- [ ] **Implement `pkg-push <pkg>`.** Its predecessor `pkg-pub` is only a partial draft; the older `publish` script is not the final interface.
- [ ] Re-test the *automated* publication flow followed by install from a fresh container.
- [ ] Verify remote GPG batch signing continues to work after agent-cache expiry/server restart.
- [ ] Host and test the proposed installer at `https://fs.alj.cx/sh/install-core.sh`.

## Immediate next checkpoint

**First verify package discovery and installation** in a fresh container by configuring `alj.sources` and running:

```bash
apt-get update
apt-cache policy core
apt-get install -y core
command -v tty-notify
```

Then implement `pkg-push` one operation at a time, following the exact manually validated order:

1. Verify/select the local archive for the requested pkg.
2. Upload only that archive via `rsync`.
3. Regenerate remote `Packages` and `Packages.gz`.
4. Regenerate remote `Release` metadata and checksums.
5. Generate and verify signed `InRelease` remotely with `gpg --batch --no-tty`.
6. Confirm the repository can be consumed by APT; fail nonzero if any stage fails.

Do not optimize for atomic publication or unattended-after-reboot key unlocking until the basic end-to-end flow succeeds.

## Roadmap

1. [ ] Automate publication (`pkg-push`).
2. [ ] Resume the tutorial on script payloads and dependencies: https://chatgpt.com/c/6addf67a-c228-83ea-8c66-259f92b94ea7
3. [ ] Write and host a single `curl ... | sh` installer for trusted APT sources (including the personal repository) and `core`.
4. [ ] Build the pkg collection:
   - [x] `core` — first shared pkg staged and built; full APT installation still unverified.
   - [ ] Headless server pkg.
   - [ ] Desktop client pkg.
5. [ ] Test all pkgs through a clean Debian environment, including upgrades and removal behavior.
6. [ ] Apply the proven bootstrap process to new VPS **Firelink**.

## Known limitations

- Live repository publication is not atomic.
- The legacy publication script may upload obsolete `dist/*.deb` artifacts.
- Version `0.0.0` is convenient during development but can create client-side cache ambiguity after republishing.
- Keep the private signing key off Git and client machines.
