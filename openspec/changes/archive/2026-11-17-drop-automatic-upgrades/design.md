# Design

## Context

- NixOS: `modules/base/auto-upgrade.nix` enables `system.autoUpgrade` (unit `nixos-upgrade`) and adds a `preStart` that bumps the inputs and a `postStart` that touches `/var/lib/nixos-central/last-update`. `modules/base/upgrade.nix` (`nixos-central upgrade`) also touches that stamp, and checks that `nixos-upgrade.service` is not running.
- Standalone homes: `modules/home/standalone.nix` enables `services.home-manager.autoUpgrade` (unit `home-manager-auto-upgrade`, with the NVIDIA pin and `nix flake update` as `preSwitchCommands`) and an `ExecStartPost` that touches `$XDG_STATE_HOME/nixos-central/last-update`. `nixos-central-internal/home-upgrade/default.nix` reads `flakeDir` and `flags` from `services.home-manager.autoUpgrade`, checks that the service is not running, and does **not** touch the stamp.
- `modules/home/update-notice.nix` computes the last update as max(stamp mtime, newest generation link mtime), defaults to 7 days, and its hint points to the daily service (`journalctl -u nixos-upgrade` / `systemctl --user status home-manager-auto-upgrade`).

## Goals / Non-Goals

**Goals:**
- No timer or service that upgrades a machine or home.
- The stamp keeps meaning "last successful `nixos-central upgrade`" on both platforms.
- The notice's default threshold is 1 day, and its hint always shows `nixos-central upgrade`.

**Non-Goals:**
- Changing `nixos-central upgrade`'s behavior beyond dropping the concurrency check and recording the stamp on standalone homes.
- Removing the reboot-pending notification or `nixos-central diff`'s staged mode; they stay for generations staged by hand.
- Daily Flatpak updates and fwupd refresh.
- Requiring a passphrase-less SSH key: it is still needed on NixOS, where `nixos-central upgrade` fetches as root through `sudo` without the user's agent. README wording changes from "daily updates" to "upgrades run as root".

## Decisions

### Delete `auto-upgrade.nix` instead of setting `system.autoUpgrade.enable = false`
Nothing else in the module is needed once the service is gone. `central-update-inputs.nix` stays (used by `upgrade.nix`); its comment drops the auto-upgrade mention. `upgrade.nix` already creates `/var/lib/nixos-central` before touching the stamp, so no tmpfiles rule is needed.
Alternative: keep the module with `enable = false` as an option for profiles. Rejected: the user asked to stop it, and an option nobody is meant to set invites drift.

### Standalone homes: inline the values `home-upgrade` took from `autoUpgrade`
`flakeDir` becomes `"${config.xdg.configHome}/home-manager"` (what home-only.sh writes and the autoUpgrade default resolved to) and the switch flags `[ "-b" "backup" ]` move to a local `let` binding in `standalone.nix`. `services.home-manager.autoUpgrade` and the `ExecStartPost` override are removed. Home-manager removes the user timer and service on the next switch.

### Record the stamp in `nixos-central upgrade` on standalone homes
After a successful `home-manager switch`, the script touches `nixos-central.updateNotice.stamp` (passed in as an argument), mirroring `upgrade.nix`. Without this, an upgrade that produces no new generation would not reset the notice, and with a 1-day threshold the user would be reminded daily even right after upgrading.

### Notice: default 1 day, unified hint
- `updateNotice.days` default becomes `1` (comparison stays "older than `days * 86400` seconds", so 20 hours is quiet and 25 hours prints).
- Hint on both platforms: `Update with: nixos-central upgrade`. On NixOS with a staged generation, the line becomes `An update is installed; reboot to use it (or update again with: nixos-central upgrade).` No mention of journals or the daily service.
- The first line keeps its format (`nixos-central: last successful update N days ago (…).`), so existing ages logic and tests stay valid.
Alternative: print on every terminal regardless of age. Rejected by the user in favour of a lower threshold.

### Drop the concurrency checks
Both `upgrade` scripts lose their `systemctl show … ActiveState` checks. Two simultaneous `nixos-central upgrade` runs were never guarded against and are not a new risk; Nix's own locking keeps the store consistent.

### Tests
- `upgrade-failures` and `home-upgrade-failures`: drop the "auto-upgrade running" cases and their fake services; add an assertion that no `nixos-upgrade.timer` / `home-manager-auto-upgrade.timer` exists.
- `overlay-upgrades`: the key-revoked case runs `nixos-central upgrade` instead of starting `nixos-upgrade.service`, and asserts lock/profile unchanged.
- `update-notice-script` and the NixOS notice test: new hint text, default threshold 1 (e.g. stamp 2 days old prints, 20 hours old is quiet).
- `home-upgrade` test: an upgrade without changes touches the stamp.
- `tests/e2e/run.py`: remove the "auto-upgrade … staged for next boot" step; keep the `nixos-central upgrade` step.

## Risks / Trade-offs

- [Machines fall behind if users ignore the notice] → The 1-day threshold makes the reminder appear in every new terminal after a day; this is the intended trade-off for user control.
- [Security fixes no longer arrive unattended] → Accepted by the request; README states that updates only happen with `nixos-central upgrade`.
- [Desktop-only users who never open a terminal see nothing] → Accepted for now; the reboot-pending notification is unaffected. A desktop reminder can be a follow-up change.
- [Existing deployments keep the old timer until they pick up this change] → Their daily run will itself fetch this change and stage it; after that boot or the next `nixos-central upgrade`, the timer is gone. Standalone homes switch immediately, so their timer disappears with the run that fetches this change.

## Migration Plan

Merge to `main`. Each machine stops auto-upgrading once a generation containing this change is active (after its last automatic run plus reboot, or after `nixos-central upgrade`). Rollback: revert the commit; machines get the timer back with their next `nixos-central upgrade`.
