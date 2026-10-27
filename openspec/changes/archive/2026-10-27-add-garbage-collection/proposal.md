# Proposal

## Why

Nothing ever removes old generations or unreferenced store paths: every daily update that changes something adds a generation, and `configurationLimit = 10` only hides old ones from the boot menu. The store only grows. On a standalone home on Arch it has reached 362 GB with a 90 % full disk; NixOS machines may have disks as small as 40 GiB and would fill up within months.

## What Changes

- NixOS machines collect garbage weekly as root: system generations older than 30 days are deleted, then unreferenced store paths.
- Every home, on NixOS machines and standalone homes, collects garbage weekly as its user: the user's own profile generations older than 30 days are deleted (home-manager on standalone homes, and the personal `nix profile`/`nix-env` profile everywhere), then unreferenced store paths. On NixOS the home is part of the system generation, but the user's personal profile lives in the user's profile directory, which root's collection does not reach.
- Runs missed while the machine was off or the user was logged out are made up soon after.
- The last working generation always remains: 30 days are kept, plus the generation that was active 30 days ago, so the existing rollback guarantees still hold.
- Collection runs on its own schedule, independent of whether updates succeed.
- NixOS machines additionally free unreferenced store paths during builds when free space drops low, so an update does not fail on a nearly full disk between weekly runs.
- The retention period and schedule are defaults that a profile (homes) or the machine's own modules can override.
- No store optimisation (hard-link deduplication) in this change.

## Capabilities

### New Capabilities

- `garbage-collection`: automatic removal of old generations and unreferenced store paths on NixOS machines and in every home, without breaking rollback.

### Modified Capabilities

None. `system-updates` "Rollback via boot menu" and `home-configuration` "Rollback to the previous home" stay as they are; the new capability must not violate them.

## Impact

- `modules/base/`: new module for the NixOS `nix.gc` timer and `min-free`/`max-free`, imported from `modules/base/default.nix`.
- `modules/home/`: new module enabling home-manager's `nix.gc`, added for every profile in `modules/user.nix` (`sharedModules`) and `lib.mkHome`, and listed as internal in `nixos-central-internal/lib/overlay.nix`.
- Tests: a VM test for both collections on NixOS, and a check of the standalone home's timer.
- README: "Updates" and "Install on another Linux distribution" mention the cleanup and its effect on rollback.
- First run on existing machines and homes deletes all generations older than 30 days (except the one active 30 days ago) and can free a lot of space at once.
