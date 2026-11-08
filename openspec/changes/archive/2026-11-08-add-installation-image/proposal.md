# Proposal

## Why

Installing today means downloading the stock NixOS image, booting it, connecting to the network and typing a `curl | sh` line served from GitHub Pages. A ready-made installation image removes the typing and the dependency on Pages, and starts the installer by itself. It also lets the end-to-end test boot exactly what users download; today the test builds its own image.

## What Changes

- Build a bootable installation image (x86_64, UEFI) from the central flake, based on the minimal NixOS installation image.
- On boot, the image offers to start the installer on the first console. It helps the user get online (`nmtui`) when there is no network, then runs the **current** installer from the central repository's default branch, not a copy frozen into the image. An image built months ago therefore installs today's configuration with today's installer.
- Publish the image as a GitHub release asset under a stable "latest" download URL, with a checksum. A workflow builds it on demand, monthly, and when the pinned NixOS release changes.
- The `curl | sh` installation from a stock NixOS image keeps working unchanged.
- The end-to-end installer test boots the published image definition.
- The README makes the image the primary way to install; the curl line stays as an alternative.

## Capabilities

### New Capabilities
<!-- None -->

### Modified Capabilities
- `installer`: adds a published installation image that starts the current installer; the existing stable-URL requirement is kept.

## Impact

- New: the image definition (flake output `packages.x86_64-linux.iso`, not a `nixosConfigurations` entry, which CI would build on every push), a release workflow, a small start-up prompt on the image's console.
- Changed: `nixos-central-internal/tests/e2e` uses the flake's image plus a serial console. Installer messages that point to nixos.org/download point to the release instead. The README's Install section changes.
- Unchanged: `install.sh` logic, machine flakes, `mkHost`, the Pages-published scripts.
- GitHub: releases with a ~1.2 GiB asset each. Older image releases can be pruned. Each release asset is limited to 2 GiB.
