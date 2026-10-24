# Design

## Context

- `modules/base/auto-upgrade.nix` uses the stock `system.autoUpgrade` with `operation = "boot"` and `flags = [ "--update-input" "central" ]` (nixos-rebuild-ng on nixos-26.05 accepts `--update-input`; see archived design D6). The unit is `nixos-upgrade.service`.
- `modules/base/try.nix` is the precedent for a user-facing command: a `writeShellApplication` with `config.system.build.nixos-rebuild` as runtime input, self-elevation via `sudo`, the target `/etc/nixos#<hostname>`, and `--refresh` so a just-pushed commit is seen.
- `modules/base/reboot-notify.nix` notifies only when `/nix/var/nix/profiles/system` differs from both `/run/booted-system` and `/run/current-system`. After a switch the profile equals the current system, so no notification is shown without any change there.

## Goals / Non-Goals

**Goals:**
- One command that does what the daily upgrade does, but with `switch` instead of `boot`.
- Upgrade semantics cannot drift from the automatic upgrade.

**Non-Goals:**
- Upgrading to a branch other than the default (`nixos-central-try` covers trying branches; persisting a branch is not wanted).
- A per-machine setting to make the *automatic* upgrade switch (considered and rejected for this change).
- A GUI/desktop entry for the command.
- Changing the reboot-notification logic.

## Decisions

### D1: Separate command `nixos-central-upgrade` in `modules/base/upgrade.nix`
Same structure as `try.nix`, imported from `modules/base/default.nix`. The `nixos-central-` prefix matches the existing command and keeps tab completion discoverable.
*Alternative:* tell users to run `sudo nixos-rebuild switch --flake /etc/nixos --update-input central`. Rejected: easy to get wrong (forgetting `--update-input` silently switches to the old lock; forgetting `--refresh` may miss a fresh commit).
*Alternative:* a second systemd unit started via `systemctl start`. Rejected: build output goes to the journal instead of the terminal, which is worse for an interactive command.

### D2: Share the update flags with the auto-upgrade
The command runs
`nixos-rebuild switch --flake /etc/nixos#<hostname> <update flags> --refresh`.
The update flags (`--update-input central`) live in `modules/base/central-update-flags.nix`, imported by both `auto-upgrade.nix` (as `system.autoUpgrade.flags`) and `upgrade.nix` (shell-escaped). If the update mechanism ever changes (e.g. the D6 fallback to `nix flake update central`), both paths change together. The lock file is written, as with the daily upgrade, so a later manual `nixos-rebuild` or daily run reproduces the same system.
*Alternative:* read `config.system.autoUpgrade.flags`. Rejected during implementation: the stock module appends `--refresh` and `"--flake /etc/nixos"` (a single string meant for unescaped interpolation) to that option, so it cannot be reused as an argument list.
*Alternative:* hard-code the flags. Rejected: two places to keep in sync.

### D3: Restore `flake.lock` if nothing was installed
nix writes the updated lock file during evaluation, before the build. To meet the "Build fails" scenario, the command copies `/etc/nixos/flake.lock` to a temp file first, and if `nixos-rebuild` fails *and* `/nix/var/nix/profiles/system` still points to the same generation as before, restores the copy. If the profile did change (the build succeeded but activation failed), the lock is kept so it matches the new default boot entry; the error from `nixos-rebuild` is shown.
*Alternative:* `nix flake update central` into a copy of `/etc/nixos`, build from there, then copy the lock back. Rejected: more moving parts and diverges from D2.

### D4: Refuse while `nixos-upgrade.service` is active
Before doing anything, the command checks the unit's `ActiveState` (`systemctl show -P ActiveState nixos-upgrade.service`) for `active`, `activating` or `reloading`; `systemctl is-active` is not enough because a running oneshot is `activating`, which it reports as inactive. If it is running, the command exits non-zero with "An automatic upgrade is running right now; try again when it has finished (journalctl -fu nixos-upgrade)".
*Alternative:* `flock` on a shared lock file in both paths. Rejected for now: the stock `system.autoUpgrade` unit would need an override of its script; the check covers the realistic case (user runs the command shortly after boot while the persistent timer catch-up runs).

### D5: Kernel hint
After a successful switch, if `readlink /run/booted-system/kernel` differs from `readlink /run/current-system/kernel`, print "The new kernel is used after the next reboot." No reboot, no prompt.

## Risks / Trade-offs

- [Auto-upgrade timer fires while the command is running (check is not a lock)] → both would compute the same `central` revision; nix store operations are safe concurrently; worst case the timer run stages a generation identical to the switched one. Accepted; revisit with D4's `flock` alternative if it is seen in practice.
- [Switching a running desktop session can restart services (e.g. display manager) mid-session] → same as any `nixos-rebuild switch`; documented in the README as "may restart services; save your work".
- [A broken `main` is activated immediately instead of only at next boot] → the user chose to run it; rollback is unchanged (previous generation in the boot menu, or `sudo nixos-rebuild switch --rollback`, documented).
- [Restoring the lock on failure (D3) relies on comparing the profile link] → covered by the build-failure step in the tests.

## Migration Plan

Additive. Machines get the command with their next update (daily upgrade + reboot, or `sudo nixos-rebuild switch --flake /etc/nixos --update-input central` once). Rollback: revert the commit; the command disappears with the next update.
