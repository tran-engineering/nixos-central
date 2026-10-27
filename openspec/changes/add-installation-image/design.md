# Design

## Context

- The e2e test (`nixos-central-internal/tests/e2e/default.nix`) already builds an image from `installation-cd-minimal.nix` with a serial console and zstd squashfs. It serves the repository over git smart HTTP and runs `install.sh` via `curl … | NIXOS_CENTRAL_FLAKE=<local url> sh`.
- The installer is already a flake output (`packages.<system>.installer`, `nixos-central-install`), built from `install.sh` unchanged.
- The stock minimal image has NetworkManager, logs in `nixos` automatically on every console, and has passwordless sudo. `install.sh`'s live-image checks (`/etc/NIXOS`, `nixos-install` present, tmpfs/overlay root) pass on any image derived from it.
- CI builds every `nixosConfigurations` entry (`host-*` checks). Pages publishes `install.sh` and `home-only.sh` and stays as it is.

## Goals / Non-Goals

**Goals:**
- Boot, answer one prompt, install. No command to type when a cable is connected.
- An image of any age installs the current configuration with the current installer.
- The test boots what users download.

**Non-Goals:**
- Offline installation, or a store pre-seeded with system closures. The install needs GitHub and cache.nixos.org anyway, and desktop closures would exceed the release asset limit.
- Credentials or secrets on the image.
- aarch64 images. NixOS hosts are x86_64 only today.
- Keyboard-layout selection. That's a separate follow-up, though the start-up prompt is the natural place for it later.

## Decisions

### Image definition in the flake, exposed as a package
`nixos-central-internal/iso/default.nix` is a NixOS module on top of `installation-cd-minimal.nix`. It sets flakes on, includes the start-up prompt, sets the image name `nixos-central-<release>-x86_64.iso`, and uses zstd compression. The flake exposes `packages.x86_64-linux.iso` (`config.system.build.isoImage`). It is not in `nixosConfigurations`, because the `host-*` rule would build a ~1.2 GiB image on every push. Nor is it in `checks`; the e2e test and the release workflow build it.

### Start-up prompt on tty1, then the current installer
A `nixos-central-start` script runs from the login shell of `nixos` on `/dev/tty1` only, so serial consoles, SSH and further VTs stay plain shells:

```
 tty1 autologin --> nixos-central-start
                     |
                     +-- GitHub reachable? --no--> "Set up the network now? [Y/n]" --> nmtui --> retry
                     |       | yes
                     |       v
                     +-- "Install nixos-central on this computer? [Y/n]"
                             | yes                         | no
                             v                             v
                     nix run "$CENTRAL#installer"      shell (hint: run nixos-central-start)
```

`CENTRAL` defaults to `github:tran-engineering/nixos-central` and honors `NIXOS_CENTRAL_FLAKE`, as `install.sh` does, so tests and branches can point elsewhere. `--refresh` makes sure a repeat attempt gets the newest default branch. Running the flake's `installer` package instead of `curl` from Pages removes the Pages dependency for the image. The script `install.sh` is the same either way, so behavior matches the curl path.

*Alternative:* run the installer copy baked into the image. Rejected: it ties every image to the installer of its build day, while the configuration it installs always comes from the default branch. A baked fallback adds little, because without GitHub the installation can't proceed anyway.

### Release workflow
`.github/workflows/iso.yml`:
- **Triggers:** `workflow_dispatch`, a monthly schedule (kernel and security fixes), and pushes to `main` that touch the image definition. A NixOS release bump is picked up by the next monthly run at the latest, or by a manual run.
- **Build:** `nix build .#packages.x86_64-linux.iso`. Fail if the file is larger than 2 GiB.
- **Publish:** create a release `iso-<YYYY-MM-DD>` with two assets, `nixos-central-x86_64.iso` and `nixos-central-x86_64.iso.sha256`. The file name has no version, so `https://github.com/tran-engineering/nixos-central/releases/latest/download/nixos-central-x86_64.iso` stays stable. The release is marked "latest", and the release text names the NixOS release and the commit.
- **Prune:** delete image releases beyond the newest three.

### e2e test boots the flake's image
`tests/e2e/default.nix` takes `packages.x86_64-linux.iso`'s module list and adds `console=ttyS0,115200`. The existing flow (curl from the test server over serial) keeps working because the prompt runs only on tty1. A new step runs `nixos-central-start` on the serial console with `NIXOS_CENTRAL_FLAKE` pointing at the test server, and checks that it reaches the installer's first question.

### Messages and README
`install.sh`'s "boot the image" messages link to the latest image instead of nixos.org/download. The README's Install section becomes:
1. download the image (with a `curl -L … | sudo dd …` example, as today, and the checksum);
2. boot it in UEFI mode;
3. answer the prompt.

The curl one-liner moves to "Already have a NixOS USB stick?".

## Risks / Trade-offs

- [The default branch is broken at install time; the image can't fall back] → Same as the curl path today. `NIXOS_CENTRAL_FLAKE=github:…/<rev>` from the shell works as an escape hatch, which the README mentions.
- [The tty1 prompt fires on a machine booted from the stick by accident] → The prompt only starts the installer. Disk changes still require typing `yes` at the wipe confirmation.
- [The image kernel is too old for very new hardware] → The minimal image follows the release's default kernel. If needed, switch the image to `linuxPackages_latest`. That doesn't affect installed machines.
- [Release assets accumulate] → Pruning keeps three.

## Migration Plan

Additive. Existing installs and the curl path are unaffected. After merging, run the workflow once manually to publish the first image before the README links to it.
