# Proposal

## Why

Machines and standalone homes update themselves silently every day, so a user only notices that updates stopped (machine offline, build failing, never rebooted into the staged generation) when something is visibly out of date. A short hint in the terminal when the setup has gone stale makes this noticeable without nagging while everything works.

## What Changes

- Successful runs of the daily upgrade, `nixos-central-upgrade` and the standalone home-manager auto-upgrade are recorded, whether or not they changed anything.
- When a user opens an interactive shell (bash, fish or zsh) and the **last successful update** is older than a threshold (default 7 days), a short notice is printed with a hint what to do. Machines that update normally show nothing, even when the central repository has been quiet for a while.
- The notice states three ages: last successful update, the running configuration (NixOS system generation or active home-manager generation), and the pinned central revision (commit date of `central` in the flake lock file).
- The hint depends on the situation: a newer generation already staged → reboot; otherwise → `nixos-central-upgrade` (NixOS) or the home-manager auto-upgrade service (standalone).
- Profiles can change the threshold or turn the notice off.
- Part of every profile, on NixOS machines and standalone homes.

## Capabilities

### New Capabilities

- `stale-update-notice`: notice in new interactive shells when the last successful update is older than a threshold.

### Modified Capabilities

None.

## Impact

- New shared home module (e.g. `modules/home/update-notice.nix`), added for every profile next to `modules/home/shell.nix` in `modules/user.nix` (`sharedModules`) and in `lib.mkHome`.
- `modules/base/auto-upgrade.nix`, `modules/base/upgrade.nix` and `modules/home/standalone.nix` record successful updates; `standalone.nix` also tells the module it runs in a standalone home.
- New option for profiles: threshold in days, `0`/disabled to turn the notice off.
- Tests: a VM test for the NixOS case and a check of the standalone case.
- README: "Updates" section mentions the notice and how to change it.
- No change to `mkHost`/`mkHome` interfaces; existing machines and homes get it with their next update.
