# Proposal

## Why

Several machines, mostly hybrid laptops plus one or two desktops, are moving to full NixOS, and all of them have modern NVIDIA GPUs. Today the installer has no NVIDIA step and `mkHost` has no NVIDIA fact, so each of these machines would need hand-written driver, PRIME and Docker configuration after install.

## What Changes

- New optional machine fact `nvidia` on `mkHost`, written into the machine flake by the installer. It defaults to `null`, so existing machine flakes build as before.
- A new central module configures machines with the fact:
  - always the open kernel modules with NVIDIA's proprietary userspace; the closed kernel modules are not offered
  - driver power management
  - the NVIDIA container toolkit, so Docker containers can use the GPU through CDI
- Hybrid laptops get PRIME offload with `nvidia-offload` and fine-grained power management, selected by bus IDs recorded in the fact.
- The driver comes from nixpkgs. Per-machine `channel` chooses `"stable"` (default) or `"unstable"`. `"unstable"` is the newest branch from nixos-unstable, built against the machine's own kernel.
- The installer detects the GPU from sysfs, shows what it found and asks for confirmation. New flags `--nvidia` and `--no-nvidia` answer without a prompt. PRIME facts are written only for machines with a battery, so a desktop with an enabled iGPU is not set up for offload.
- The installer checks that `download.nvidia.com` is reachable before the disk is erased when NVIDIA is selected.
- `nix flake check` builds both driver channels, so a driver that no longer builds keeps the weekly lock update from reaching machines.
- `nixos-central upgrade` says when a new driver needs a reboot, not only a new kernel.
- The README documents the fact, the flags, `nvidia-offload`, the channel trade-off and GPU access from Docker.

**Out of scope:** GPUs older than Turing, closed kernel modules, PRIME sync and reverse sync, pinning a driver version outside nixpkgs, Docker's `nvidia` runtime, moving existing NixOS machines automatically, and standalone homes (`mkHome`), which keep using the host distribution's driver.

## Capabilities

### New Capabilities

- `nvidia-graphics`: how a machine with the `nvidia` fact is configured: open kernel modules, driver channel, PRIME offload on hybrid laptops, power management, container GPU access, and continuous verification of the driver builds.

### Modified Capabilities

- `host-configuration`: the machine flake and the `mkHost` entry point gain the optional `nvidia` fact.
- `installer`: GPU detection, confirmation and flags; `download.nvidia.com` reachability when NVIDIA is selected; the summary shows the NVIDIA configuration.
- `system-updates`: `nixos-central upgrade` reports that a driver change needs a reboot.

## Impact

- **Code:** `modules/options.nix`, new `modules/base/nvidia.nix`, `modules/base/default.nix`, `modules/base/upgrade.nix`, `nixos-central-internal/lib/default.nix`, `nixos-central-internal/templates/host/flake.nix`, `nixos-central-internal/installer/install.sh`, a new detection script next to it, `flake.nix`, `nixos-central-internal/tests/default.nix`, `README.md`.
- **Public interface:** `mkHost` gains an optional argument. Machine flakes need no edits.
- **Installs and updates of NVIDIA machines:** they download the driver from NVIDIA and build the userspace package locally, because it is not in `cache.nixos.org`. The `"unstable"` channel also compiles the kernel module locally.
- **CI:** `nix flake check` gets longer. A driver build failure on either channel leaves the weekly lock update PR open for a human, which holds back updates for all machines until it is resolved.
- **Hardware testing:** VMs have no NVIDIA GPU. PRIME, GDM, suspend and containers can only be verified on real machines.
