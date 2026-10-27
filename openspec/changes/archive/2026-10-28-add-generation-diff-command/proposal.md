# Proposal

## Why

The daily upgrade stages a new generation and the desktop says "Update ready –
reboot when convenient", but nothing tells the user *what* the update contains.
`nh` shows a package diff (via `dix`) after every switch; machines managed by
nixos-central have no equivalent, so users reboot (or run
`nixos-central-upgrade`) blind, and can't see afterwards what the last update
changed.

## What Changes

- New command `nixos-central-diff` on NixOS machines, run as any user (no
  `sudo`). It shows a `dix` package diff and picks what to compare by itself:
  - an update is staged (default boot entry differs from the running system):
    running system → staged generation, headed as "pending on next reboot";
  - otherwise: the generation before the newest one → the newest one, headed
    with both generation numbers.
- The same command on standalone homes: previous home-manager generation →
  current one (homes switch immediately, so nothing is ever staged).
- With no earlier generation to compare against, the command says so and
  succeeds.
- The reboot-pending notification points to the command: its body mentions
  `nixos-central-diff`. The title stays "Update ready – reboot when convenient".
- README "Updates" and "Install on another Linux distribution" document the
  command.

Not in scope: a closure diff in the flake-update pull requests (would require
building whole systems in CI).

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `system-updates`: new requirement for `nixos-central-diff` on NixOS; the
  reboot-pending notification requirement now names the command.
- `home-configuration`: new requirement for `nixos-central-diff` on standalone
  homes.

## Impact

- New script package (shared by NixOS and homes) under
  `nixos-central-internal/`, a new `modules/base/diff.nix`, and an entry in
  `home.packages` in `modules/home/standalone.nix`.
- `modules/base/reboot-notify.nix` (notification body).
- New runtime dependency: `dix` from the pinned nixpkgs (small, already
  packaged).
- `nixos-central-internal/tests/default.nix`: VM tests for both variants.
- `README.md`.
