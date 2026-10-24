# Proposal

## Why

Updates from the central repository only take effect after the next reboot: the daily auto-upgrade and the documented manual trigger (`sudo systemctl start nixos-upgrade`) both run `nixos-rebuild boot`. A user who just got a pull request merged (e.g. a new package in their profile) has to reboot to use it, or abuse `nixos-central-try main`, which does not persist and leaves `/etc/nixos/flake.lock` stale.

## What Changes

- Add a command `nixos-central-upgrade` that, on demand, updates the `central` input in `/etc/nixos` to the latest `main` and **switches** to the result: it is activated in the running system immediately *and* becomes the default boot entry.
- It uses the same update semantics as the daily auto-upgrade (only `central` is updated, `flake.lock` is written), so the next daily run builds the same thing.
- It self-elevates with `sudo` like `nixos-central-try`, and refuses to run while the automatic upgrade is in progress.
- The daily automatic upgrade is unchanged: it still only stages for the next boot and never reboots.
- README "Updates" section documents the command next to the existing "run an update right away" (boot-only) option.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `system-updates`: adds a requirement for an on-demand upgrade that activates immediately and persists as the default boot entry.

## Impact

- New module `modules/base/upgrade.nix` (or equivalent), imported from `modules/base/default.nix`.
- `README.md` "Updates" section.
- E2E test `nixos-central-internal/tests/e2e/run.py` gains a step exercising the command.
- No change to `lib.mkHost`'s interface or to machine flakes; existing machines get the command with their next update.
