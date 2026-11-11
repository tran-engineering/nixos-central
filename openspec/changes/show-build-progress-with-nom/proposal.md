# Proposal

## Why

Installing a machine and running `nixos-central upgrade` mean long builds. Today they only show Nix's plain log, or a quiet terminal for minutes. Users can't tell whether anything is happening, how much is left, or what is being downloaded or built. `nh switch`, which some users know, shows this as a live tree with progress, using [nix-output-monitor](https://github.com/maralorn/nix-output-monitor) (`nom`). The repository already uses dix for package diffs, the other half of nh's output. The live progress display is the missing piece.

## What Changes

- Long builds started by a user show nom's live progress display (what is downloaded or built, how much is done, and elapsed time) when they run on a capable terminal:
  - `install.sh`: installing NixOS onto the target disk
  - `home-only.sh`: the first activation of the home
  - `nixos-central upgrade` on NixOS machines, with or without `--private`
  - `nixos-central upgrade` on standalone homes, with or without `--private`
- Each of these builds the configuration first with nom, then activates the finished result with the same tool as today (`nixos-install`, `nixos-rebuild switch`, `home-manager switch`). Activation, rollback and lock-file handling stay as they are.
- On a terminal that can't show it (serial console, `TERM=dumb`, output not a terminal), or when `NIXOS_CENTRAL_PLAIN` is set, the build prints Nix's normal log as today.
- The installer's log file (`/tmp/nixos-central-install.log`) still gets the complete build log, including any error, without nom's screen redraws. While the live display is shown, these log lines are in Nix's machine-readable JSON-lines format.
- The installation image includes `nix-output-monitor`, as it does gum. Other live images fetch it from the central repository's nixpkgs, the same way the installer fetches gum.

**Assumptions (change them if needed):**

- No package diff and no confirmation before switching. `nixos-central upgrade` keeps running without questions, and `nixos-central diff` stays the way to see changes.
- Activating with the existing tools evaluates the configuration a second time. This adds a few seconds, but nothing is built twice.

**Out of scope:** the daily automatic upgrades (nobody watches them), `nixos-central try`, adopting `nh` itself, and progress for disko's partitioning step.

## Capabilities

### New Capabilities

- `build-progress`: how long builds started by a user are shown. This covers the live progress display on capable terminals, the plain fallback, which commands it applies to, and that the install log stays complete.

### Modified Capabilities

(none). Install, upgrade and rollback behavior in `installer`, `home-installer`, `system-updates` and `home-configuration` does not change. Only the way the build is displayed changes.

## Impact

- **Code:** `nixos-central-internal/iso/default.nix`, `nixos-central-internal/installer/install.sh`, `nixos-central-internal/installer/home-only.sh`, `modules/base/upgrade.nix`, `nixos-central-internal/home-upgrade/default.nix`, `modules/home/standalone.nix` (if the home upgrade needs new arguments), `nixos-central-internal/tests/default.nix`, `README.md`.
- **Dependencies:** `nix-output-monitor` from the central repository's nixpkgs. It is part of the upgrade commands' closure on installed machines and included in the installation image. Elsewhere, the installers fetch it at install time.
- **Tests:** the e2e test runs the installer and `nixos-central upgrade` with `TERM=dumb`, so it covers the plain path. The nom path needs its own check.
