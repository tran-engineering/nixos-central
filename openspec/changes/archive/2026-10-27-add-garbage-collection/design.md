# Design

## Context

- No collection is configured anywhere. `modules/base/default.nix` sets `boot.loader.systemd-boot.configurationLimit = 10`, which only limits boot entries.
- The daily upgrade (`modules/base/auto-upgrade.nix`) runs `boot`, so a machine that isn't rebooted can have several generations staged after the one it runs. `/run/current-system` and `/run/booted-system` are GC roots for their store paths, but not for their generation links (which the boot menu is built from).
- home-manager (pinned `release-26.05`) has `nix.gc` (`modules/services/nix-gc.nix`): a systemd user service + timer running `nix-collect-garbage <options>` with the home's `nix.package`, falling back to `pkgs.nix`. It works for the NixOS-module and the standalone mode.
- Standalone home-manager writes its generations to `~/.local/state/nix/profiles` (or `/nix/var/nix/profiles/per-user/$USER`). Embedded in NixOS it writes none (`home-manager.enableLegacyProfileManagement` defaults to false): the home is part of the system generation. On both, the user's personal profile (`nix profile`, `nix-env`) lives in the user's profile directory. Root's `nix-collect-garbage --delete-older-than` only walks `/nix/var/nix/profiles`.
- `--delete-older-than Nd` deletes non-current generations older than N days, except the newest one older than N days (the one active at the cutoff). The tests confirm this on the pinned Nix.
- `modules/home/update-notice.nix` reads the creation time of the newest and the running generation; both survive collection.

## Goals / Non-Goals

**Goals:**
- Bounded store growth on NixOS machines and standalone homes, with no root needed for homes.
- Keep the rollback guarantees of `system-updates` and `home-configuration`.

**Non-Goals:**
- Store optimisation (`nix.optimise`), decided against for now.
- `min-free`/`max-free` on standalone homes: that is host-wide `nix.conf`, owned by whoever installed Nix.
- Collecting other users' profiles on NixOS (only the primary user has a home from this repository).

## Decisions

**System: own `nixos-central-gc` service and timer** in `modules/base/gc.nix`, rather than NixOS's `nix.gc`. NixOS's `nix.gc` would run `nix-collect-garbage --delete-older-than 30d`, which can delete the generation the machine is running or booted into when newer staged generations exist (e.g. running gen 50 days old, staged gens 45 and 1 day old → 50 is deleted, leaving the known-good system out of the boot menu). The script:
1. Lists generations of `/nix/var/nix/profiles/system` (`nix-env -p … --list-generations`, or link mtimes).
2. Selects what `--delete-older-than` would delete, then removes from that set the current one, the generations `/run/booted-system` and `/run/current-system` point to.
3. `nix-env -p /nix/var/nix/profiles/system --delete-generations <numbers>`, then `nix-collect-garbage` (no `-d`; store paths only).
4. If generations were deleted, rewrites the boot menu with `/nix/var/nix/profiles/system/bin/switch-to-configuration boot`. It uses the profile's current (possibly staged) generation, so the default boot entry stays the same. `/run/current-system/bin/switch-to-configuration` would wrongly make the running system the default.
Timer: weekly, `Persistent = true`, randomized delay like the upgrade.
Options under `nixos-central.gc` on the NixOS side: `enable` (default true), `keepDays` (default 30), `dates` (default `weekly`); plain option defaults, so a machine module sets them normally.
Alternative: NixOS `nix.gc` plus a separate protection hook — rejected: no hook between "delete generations" and "collect".

**Homes: home-manager `nix.gc`** in a new `modules/home/gc.nix`, part of every profile (`sharedModules`, `mkHome`, internal in `overlay.nix`): `automatic = lib.mkDefault true`, `dates = lib.mkDefault "weekly"`, `persistent = true`, `options = lib.mkDefault "--delete-older-than 30d"`. On NixOS it only finds the user's personal profile; on standalone homes also the home-manager generations. In a home the active generation is always the newest, so plain `--delete-older-than` keeps the rollback target; no custom script needed. Overriding works through the existing home-manager options (`nix.gc.options = "--delete-older-than 90d";`).

**Free space during builds** (NixOS): `nix.settings.min-free = lib.mkDefault (2 * 1024³)` and `max-free = lib.mkDefault (10 * 1024³)`, sized for the 40 GiB minimum disk. Nix's auto-GC only removes unreferenced paths, never generations.

**Concurrency:** Nix serializes collection against builds with its own locks and temp roots; the system and home timers may run at the same time, which is safe. Each run also collects paths freed by the other's earlier run.

## Risks / Trade-offs

- [First run on long-lived machines frees a lot at once, and takes a while] → expected; runs in the background with low priority (`Nice`, `IOSchedulingClass=idle`).
- [User timer only runs while the user's systemd instance runs] → desktop users log in regularly; `Persistent` catches up.
- [Home and system timers both walk the whole store] → weekly, low priority; acceptable.
- [The custom system script misjudges a generation] → VM test covers current, booted, running and cutoff cases; the script never passes the current generation to `--delete-generations`.

## Migration Plan

Ships with the next daily update. Existing machines and homes get their first collection within a week (or right after boot/login, if the persistent timer has never run). Turning it off: `nixos-central.gc.enable = false;` in a machine module, `nix.gc.automatic = false;` in a profile.
