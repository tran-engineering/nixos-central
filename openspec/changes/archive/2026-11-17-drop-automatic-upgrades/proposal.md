# Proposal

## Why

Machines and standalone homes currently upgrade themselves every day in the background (`nixos-upgrade` on NixOS, `home-manager-auto-upgrade` on standalone homes). Users should decide when their system changes: instead of a silent daily build, they are told in the terminal how long ago the last update was and which command installs the latest one.

## What Changes

- **BREAKING** NixOS machines no longer run the daily `nixos-upgrade` service: no update is fetched, built or staged for the next boot without the user running `nixos-central upgrade`.
- **BREAKING** Standalone homes no longer run the daily `home-manager-auto-upgrade` service; they update only through `nixos-central upgrade`.
- `nixos-central upgrade` no longer has to guard against a running automatic upgrade (the "no concurrent upgrades" checks go away with the services).
- `nixos-central upgrade` on a standalone home records each successful run as the last update (so far only the daily service did), so an upgrade that changes nothing still resets the age.
- The terminal notice becomes the regular reminder:
  - default threshold lowered from 7 days to **1 day**: a new interactive shell prints the notice once the last update is more than a day old (profiles can still change the threshold or turn it off with `0`);
  - it always states how long ago the last update was and shows the command to install the latest one, `nixos-central upgrade`, on NixOS and standalone homes alike (instead of pointing to the daily service's journal or status);
  - if a newer system generation is already staged, it additionally says to reboot to use it.
- Requirements and documentation that rely on the daily upgrade (unattended overlay fetch, NVIDIA pin and GPU setup in the daily home upgrade, journal output of automatic upgrades, installer summaries, README "Updates") are reworded or removed.
- Out of scope: daily Flatpak updates and the fwupd metadata refresh stay as they are; the reboot-pending desktop notification stays for generations staged by hand (e.g. `nixos-rebuild boot`).

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `system-updates`: remove the daily automatic upgrade, the no-automatic-reboot requirement tied to it, and the concurrency guard; reword the reboot-pending notification and `nixos-central diff` scenarios that assumed a daily staged upgrade.
- `stale-update-notice`: default threshold 1 day; the last update no longer includes automatic upgrades but does include `nixos-central upgrade` on standalone homes; the hint always shows `nixos-central upgrade`.
- `home-configuration`: remove the daily automatic home upgrade and the concurrency guard; the NVIDIA pin and GPU setup requirements are replaced by versions that only concern `nixos-central upgrade`.
- `private-overlay`: the unattended-fetch requirement is replaced by one for `nixos-central upgrade` fetching the overlay as root with the primary user's key (host keys still pinned); the failure scenario refers to `nixos-central upgrade`.
- `installer`: the first-boot overlay scenario refers to `nixos-central upgrade` instead of the daily upgrade.
- `home-installer`: the summary no longer mentions or schedules automatic updates.
- `build-progress`: remove the requirement about automatic upgrades' journal output.
- `desktop-apps`: the Flatpak independence requirement refers to system upgrades in general, not the automatic NixOS upgrade.

## Impact

- Code: `modules/base/auto-upgrade.nix` (removed; the stamp directory stays), `modules/base/default.nix`, `modules/base/upgrade.nix`, `modules/base/flatpak.nix` (comment), `modules/home/standalone.nix`, `modules/home/update-notice.nix`, `nixos-central-internal/home-upgrade/default.nix`, `nixos-central-internal/home-upgrade/nvidia-pin.nix` (comment), `nixos-central-internal/installer/home-only.sh` (summary).
- Tests: `nixos-central-internal/tests/default.nix` (upgrade-failures, overlay-upgrades, home-upgrade-failures, update-notice-script and the NixOS notice test), `nixos-central-internal/tests/e2e/run.py` (auto-upgrade step).
- Docs: `README.md` (intro, install, standalone homes, NVIDIA, private overlay, Updates).
- Existing machines and homes: the timers disappear on their next `nixos-central upgrade`. Until then (they will not upgrade themselves into this change), the old daily service keeps running; once a machine has picked up this change, it no longer updates without the user.
