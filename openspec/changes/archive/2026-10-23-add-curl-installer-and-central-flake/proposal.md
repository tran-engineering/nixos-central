# Proposal

## Why

Installing NixOS for friends or team members today means either a manual install or a dev-machine-driven push (as in k-nixos) that requires repo access and a second computer. We want a single, central NixOS configuration that many independent machines follow, installable by anyone from a booted NixOS USB image with one `curl | sh` command and kept up to date without per-machine maintenance.

## What Changes

- New repository `tran-engineering/nixos-central` (independent of k-nixos) containing a central flake that exposes a `lib.mkHost` builder, shared NixOS modules, selectable desktop modules, and user profiles.
- New installer script published via GitHub Pages at `https://tran-engineering.github.io/nixos-central`, runnable as `curl -sL https://tran-engineering.github.io/nixos-central | sh -s -- [--hostname H] [--user U] [--desktop D] [--disk DEV]`:
  - prompts (via `/dev/tty`) for anything not given as a flag: hostname, username, desktop, LUKS passphrase, user password (optionally reusing the LUKS passphrase)
  - auto-selects the first internal disk of at least 40 GiB, never the boot USB, and wipes it only after a typed confirmation
  - partitions with disko (GPT, EFI, LUKS, btrfs), generates hardware config, writes a thin local flake to `/etc/nixos`, runs `nixos-install`
- Thin per-machine flake in `/etc/nixos` holding only machine facts (hostname, primary user, desktop, hardware config) and consuming the central repo as the `central` input.
- User profiles resolved at evaluation time: `users/<name>/` in the central repo if it exists, otherwise `users/_default/`. Customization happens only through the central repo (PRs).
- Automatic updates: daily `system.autoUpgrade` with `operation = "boot"`, bumping the `central` input, plus a desktop notification when a newer generation awaits a reboot.
- Experimentation support: `nix-shell -p` / `nix shell nixpkgs#…` pinned to the system's nixpkgs, and a `nixos-central-try <branch>` helper that activates a branch of the central repo via `nixos-rebuild test` (reverted on reboot).

## Capabilities

### New Capabilities
- `installer`: the `curl | sh` bootstrap from a NixOS live image — argument handling, interactive prompts, disk detection and confirmation, LUKS setup, partitioning, local flake generation, and system installation; including its publication via GitHub Pages.
- `host-configuration`: the central flake's host builder and the thin per-machine flake contract — hostname, primary user, desktop selection, shared base modules, and nixpkgs pinning for ad-hoc shells.
- `user-profiles`: how a machine's user gets its configuration — repo-based per-user profiles with fallback to the shared `_default` profile, and account setup (admin rights, initial password).
- `system-updates`: how machines stay current with the central repo — scheduled boot-mode auto-upgrade, reboot-pending notification, and trying unmerged branches safely.

### Modified Capabilities
<!-- none: greenfield project -->

## Impact

- New repository content: `flake.nix`, `lib/`, `modules/`, `modules/desktops/`, `users/_default/`, `install.sh`, GitHub Pages workflow.
- External dependencies: nixpkgs, home-manager, disko (flake inputs); GitHub Pages for script hosting; GitHub as the source for machine updates.
- Every installed machine pulls from `tran-engineering/nixos-central` main daily: a broken commit on main affects all machines at their next reboot (mitigated by boot-mode upgrades and systemd-boot rollback).
- Out of scope: Wi-Fi setup on the live image, TPM2/unattended LUKS unlock, machine-local customization layers, multiple users per machine at install time, resolving username collisions in `users/`.
