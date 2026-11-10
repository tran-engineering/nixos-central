# Proposal

## Why

Installed machines run on UTC: nothing in the central repository sets a time zone, and the installer never asks for one. Clocks, logs, notifications and the daily upgrade times are therefore an hour or two off for every user in Switzerland, who expected `Europe/Zurich`. At the same time, every choice in the installer is a free-text prompt (`Desktop [kde]:`), and a wrong value is only rejected after it is typed. With about 400 time zones, typing one from memory is not workable, so adding the question is a good moment to switch the installer's choices to real menus.

## What Changes

- New machine fact `timeZone` (e.g. `"Europe/Zurich"`), recorded in `/etc/nixos/flake.nix` by the installer and passed through `mkHost`. It sets the system time zone. Machines whose flake has no `timeZone` get `Europe/Zurich`.
- The installer asks for the time zone after the keyboard layout. It suggests `Europe/Zurich`, offers every zone of the live system's time zone database, and accepts a new `--time-zone NAME` flag. Unknown zones are rejected.
- On a capable terminal, the installer and the installation image's start-up prompt use [gum](https://github.com/charmbracelet/gum) menus for their choices:
  - a filterable list for the time zone
  - a list with the default preselected for keyboard layout, desktop and overlay profile
  - yes/no confirmations for the NVIDIA driver, reusing the disk passphrase as the login password, setting up a private overlay, retrying or skipping the overlay, rebooting, and the image's network and install offers
- Unchanged, by design: the typed `yes` before the disk is erased, hidden passphrase and password entry, and free-text hostname, username and overlay URL.
- On a terminal that can't show menus (serial console, `TERM=dumb`, or no gum available), every question keeps today's plain prompt, with the same text and answers. Unattended and scripted installs keep working.
- The summary at the end shows the time zone.
- README: the new fact, flag and question, and how to change the time zone later.

**Assumptions (change them if needed):**

- Existing machines without the fact move from UTC to `Europe/Zurich` on their next update. This matches the expected behavior; a machine that wants UTC records `timeZone = "UTC"`.
- The suggested zone is always `Europe/Zurich`. There is no detection from IP address or location.
- The uncommitted `time.timeZone = lib.mkDefault "Europe/Zurich"` in `modules/base/default.nix` (made before this change) is replaced by the fact.

**Out of scope:** an automatic time zone that follows the machine (automatic-timezoned/geoclue), menus in the home installer (`home-only.sh`), choosing the disk from a menu (it is still selected automatically), the NTP client (NixOS's default `systemd-timesyncd` stays as it is), and the locale.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `host-configuration`: the machine flake and `mkHost` gain the optional `timeZone` fact; the shared base sets the machine's time zone from it, defaulting to `Europe/Zurich`.
- `installer`:
  - asks for and validates the time zone, with `--time-zone` to skip the question
  - shows the time zone in the summary
  - uses menus for choices on capable terminals, with plain prompts as the fallback
  - also states two existing behaviors the spec never recorded: the `--keyboard-layout` flag and the keyboard layout question

## Impact

- **Code:** `modules/options.nix`, `modules/base/default.nix` (or a new `modules/base/time-zone.nix`), `nixos-central-internal/lib/default.nix` (`hostModules`), `nixos-central-internal/templates/host/flake.nix`, `nixos-central-internal/installer/install.sh`, `nixos-central-internal/iso/default.nix` and `start.sh`, `nixos-central-internal/tests/default.nix`, `nixos-central-internal/tests/e2e/run.py`, `README.md`.
- **Public interface:** `mkHost` gains an optional argument, and the installer gains a flag. Machine flakes need no edits.
- **Existing machines:** the clock shows `Europe/Zurich` time after the next update, unless they record another zone.
- **Dependencies:** `gum` from the central repository's nixpkgs. It is included in the installation image, and other live images fetch it when the installer runs.
