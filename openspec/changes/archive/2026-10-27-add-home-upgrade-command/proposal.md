# Proposal

## Why

Standalone homes (Linux without NixOS) only update through the daily
`home-manager-auto-upgrade` timer. To get a just-merged central change or a
just-pushed overlay change right away, users have to know and type
`nix flake update central private --flake ~/.config/home-manager && home-manager switch --flake ~/.config/home-manager`.
NixOS machines already have `nixos-central-upgrade` for this; homes should have
the same command. And after pushing only an overlay change, updating only the
overlay (without also taking whatever is new in central) is the common case on
both kinds of machines.

## What Changes

- Standalone homes get a `nixos-central-upgrade` command: it updates `central`
  and, if declared, `private` in `~/.config/home-manager` to their latest
  revisions and activates the result right away, like the daily upgrade.
  It runs as the user (no `sudo`).
- It refuses to start while `home-manager-auto-upgrade` is running, and on
  failure leaves `flake.lock` and the active home as they were.
- `nixos-central-upgrade --private` (NixOS and standalone homes) updates only the
  `private` input and activates the result; `central` stays at its locked
  revision. Without an overlay declared it fails and changes nothing.
- README: the command in "Install on another Linux distribution" and "Private
  overlay"; `--private` under "Updates".

No breaking changes: `nixos-central-upgrade` without arguments behaves as before
on NixOS.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `home-configuration`: new requirements for upgrading a standalone home
  immediately on demand (all inputs or only the overlay) and for refusing to run
  concurrently with the daily upgrade.
- `system-updates`: `nixos-central-upgrade` gains `--private`, which updates only
  the overlay input.

## Impact

- `modules/home/standalone.nix` (new package in standalone homes), a new script
  module next to it.
- `modules/base/upgrade.nix` (argument parsing, `--private`).
- `nixos-central-internal/tests/default.nix`: VM tests for the home command and
  for `--private` on NixOS.
- `README.md`.
