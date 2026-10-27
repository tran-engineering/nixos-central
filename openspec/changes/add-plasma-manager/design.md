# Design

## Context

- Private overlays have no inputs (see `private-overlay`), so any home-manager module an overlay uses has to come from central.
- Every profile already gets central's own home modules through `home-manager.sharedModules` (NixOS) and `lib.mkHome` (standalone): `shell.nix`, `private.nix`.
- `nixos-central-internal/lib/nixpkgs.nix` is the single package configuration for stable and `pkgs.unstable`, on NixOS and standalone homes.
- k-nixos used plasma-manager the same way (`home-manager.sharedModules`) and had the same Electron exception for logseq.

## Goals / Non-Goals

**Goals:**
- `programs.plasma.*` usable in any profile or overlay, on every platform central supports.
- `pkgs.unstable.logseq` installable without per-profile configuration.

**Non-Goals:**
- Plasma defaults set by central. The module is only made available.
- A general mechanism for overlay-requested insecure packages.

## Decisions

### plasma-manager follows central's inputs
`inputs.plasma-manager.inputs.nixpkgs.follows = "nixpkgs"` and `inputs.home-manager.follows = "home-manager"`, as k-nixos did. That keeps one nixpkgs and one home-manager. The flake-update workflow bumps it daily with the rest, and CI evaluates it through `users/ci-modules`.

*Alternative:* each overlay pins its own plasma-manager. Not possible, because overlays have no inputs.

### Added to every profile
The module only defines options. With `programs.plasma.enable` unset, plasma-manager writes no files, so profiles that don't use it are unaffected (task 1.1 verifies unchanged activation packages). It's added next to `shell.nix`/`private.nix`, not as a `centralModules` entry, because it provides options rather than tools a profile opts into.

### One named Electron exception
`permittedInsecurePackages = [ "electron-39.8.10" ]` in the shared config, with a comment. Naming the exact version keeps every other insecure package failing. It must be updated or removed when nixos-unstable's logseq moves to another Electron; evaluation fails visibly at that point (the daily flake-update PR's CI) if the exception no longer matches.

## Risks / Trade-offs

- [plasma-manager breaks with a home-manager update] → It follows central's home-manager, so the flake-update PR's CI catches it before merge.
- [An insecure Electron is installable for everyone] → Only profiles that install logseq (or something else built on that exact Electron) get it. The exception is visible in one place.
