# Tasks

Assumption: the command is named `nixos-central-upgrade` (matches `nixos-central-try`); the daily auto-upgrade stays boot-only (user decision).

## 1. Command

- [x] 1.1 Add `modules/base/upgrade.nix`: `writeShellApplication` `nixos-central-upgrade` (usage/`--help`, sudo self-elevation as in `try.nix`), running `nixos-rebuild switch --flake /etc/nixos#<hostname>` with the update flags shared with `auto-upgrade.nix` via `modules/base/central-update-flags.nix` (shell-escaped) plus `--refresh` (design D1, D2); import it in `modules/base/default.nix`; verify `nix eval .#nixosConfigurations.ci-kde.config.environment.systemPackages --apply 'map (p: p.name)'` lists it and `nix build` of the script shows the interpolated `--update-input central`
- [x] 1.2 Add the `nixos-upgrade.service` guard (design D4): exit non-zero with the "automatic upgrade is running" message before touching anything; verify with a new VM test `upgrade-failures` in `nixos-central-internal/tests/default.nix` (desktop `none`, `nixos-upgrade` script overridden to `sleep infinity`, started with `--no-block`) that the command fails, prints the message and leaves `/etc/nixos` and `/nix/var/nix/profiles/system` unchanged
- [x] 1.3 Add lock restore on failure (design D3): back up `/etc/nixos/flake.lock`, restore it if `nixos-rebuild` fails and the system profile still points to the previous generation; verify in the `upgrade-failures` VM test that with a local `central` whose new commit fails to evaluate the command fails and `flake.lock` checksum and profile are unchanged
- [x] 1.4 Add the kernel hint (design D5): after success, print "The new kernel is used after the next reboot." when `/run/booted-system/kernel` and `/run/current-system/kernel` differ; verify by reading the script and in the e2e run (2.1) that the message is absent when the kernel did not change
- [x] 1.5 Run `nix flake check` and verify all checks, including the new VM test, pass

## 2. End-to-end and documentation

- [x] 2.1 Extend `phase_installed` in `nixos-central-internal/tests/e2e/run.py` after the final reboot: run `nixos-central-try alice-wip`, then push a new `main` commit adding `home.file.upgrade-marker`, run `nixos-central-upgrade`; check the marker exists immediately, `try-marker` is gone, `flake.lock` changed, boot entries +1, `readlink -f /nix/var/nix/profiles/system` equals `/run/current-system`; reboot and check the marker is still present and the booted system equals that generation; verify `nix run --impure -f nixos-central-internal/tests/e2e` passes
- [x] 2.2 Update README "Updates": add `nixos-central-upgrade` ("install and use the latest update now; may restart services, save your work"), clarify that `sudo systemctl start nixos-upgrade` only stages for next boot, and mention `sudo nixos-rebuild switch --rollback`; verify the documented commands match the script's name and usage output

## Workflow follow-up

- Archive the change after review, syncing the `system-updates` delta into `openspec/specs/system-updates/spec.md`.
