# Design

## Context

- NixOS: `modules/base/upgrade.nix` builds `nixos-central-upgrade` (re-execs with
  `sudo`, refuses while `nixos-upgrade.service` is active, backs up
  `/etc/nixos/flake.lock`, runs `nixos-rebuild switch` with
  `central-update-flags.nix` and `--refresh`, restores the lock if the system
  profile didn't change). It takes no arguments.
- Standalone homes: `modules/home/standalone.nix` configures home-manager's
  `services.home-manager.autoUpgrade` (user unit `home-manager-auto-upgrade.service`):
  `nix flake update central [private]` as `preSwitchCommands`, then
  `home-manager switch --flake <flakeDir> -b backup`. It also installs
  `nixos-central-private` via `callPackage ../../nixos-central-internal/private`.
- Every file in `modules/home/` that isn't listed as internal in
  `nixos-central-internal/lib/overlay.nix` becomes a `centralModules` name, an
  interface checked by the `central-modules` flake check.
- The home generation is `~/.local/state/nix/profiles/home-manager`.

## Goals / Non-Goals

**Goals:**
- One command name on every machine, same failure guarantees as the NixOS one.
- `--private` on both, for "I just pushed an overlay change".

**Non-Goals:**
- `nixos-central-try` for homes.
- Other selective updates (e.g. `--central` only); the no-argument form covers it
  for machines without an overlay.

## Decisions

### Same name, `nixos-central-upgrade`, on homes
Users and the README learn one command; `home-only.sh` already tells NixOS users
to use it. *Alternatives:* `nixos-central-update` (a second name for the same
thing, and "update" vs "upgrade" would be confusing next to the existing
command); a shell alias (not available outside interactive shells, can't do the
lock restore). The two never meet: standalone homes are refused on NixOS by
`home-only.sh`, and NixOS-managed homes don't import `standalone.nix`.

### Home command lives in `nixos-central-internal/home-upgrade/`
Packaged with `callPackage`, like `nixos-central-private`, and added to
`home.packages` in `standalone.nix`. Arguments: `flakeDir` (from
`services.home-manager.autoUpgrade.flakeDir`), whether an overlay is declared
(`nixos-central.private.enable`), and the switch flags. Not a file in
`modules/home/`, so it doesn't become a `centralModules` name.

### Inputs to update are decided once, from the same option
`standalone.nix` computes the input list (`central` plus `private` if enabled)
once and uses it for both `preSwitchCommands` and the command, like
`central-update-flags.nix` does on NixOS, so the daily and manual upgrades can't
drift apart. `--private` replaces the list with `private`; if no overlay is
declared, the command stops before touching anything ("This home has no private
overlay"), on NixOS likewise ("This machine has no private overlay").

### Home flow mirrors the NixOS script
1. Parse arguments (`--private` or none; else usage, exit 2).
2. Refuse if `systemctl --user show -P ActiveState home-manager-auto-upgrade.service`
   is `active`, `activating` or `reloading`.
3. Back up `flake.lock`, record the `home-manager` profile link.
4. `nix flake update <inputs> --flake <flakeDir> --refresh` (`--refresh` so a
   commit pushed a minute ago isn't hidden by the fetcher cache), then
   `home-manager switch --flake <flakeDir> -b backup`.
5. On failure: profile link unchanged → restore the lock, "nothing was
   changed"; changed → "installed, but activating it failed" (rollback via
   `home-manager generations`).

Runs as the user; no `sudo`, so it fetches the overlay with the user's own SSH
setup, as the daily upgrade does.

### Tests
- NixOS: extend the existing `upgrade-failures`/`overlay-upgrades` VM tests with
  `--private` (only `private` reported as updated; missing overlay refused).
- Home: a VM test with a lingering user, a stub `home-manager-auto-upgrade`
  user unit (`sleep infinity`) and the home command package (built from a
  `ciHome` config) covering: build failure restores the lock, refusal during the
  automatic upgrade, `--private` without overlay, unknown argument. A stub
  central can't produce a real home without network, so the success path is
  verified by hand on a standalone home (a task), as the NixOS success path is
  covered by the end-to-end run.

## Risks / Trade-offs

- [Check-then-run race with the timer starting right after the check] → Same as
  on NixOS; both would write the same lock, and home-manager serializes profile
  updates. Accepted.
- [`--private` builds an overlay against an older central] → That's the point
  (central unchanged); the overlay already has to build against the locked
  central for the daily upgrade.
- [`nixos-central-upgrade` on a home started from the old (pre-change) home]
  → The command appears with the first upgrade that includes it; nothing to
  migrate.
