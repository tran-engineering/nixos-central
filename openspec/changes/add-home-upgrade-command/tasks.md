# Tasks

## 1. Home command

- [x] 1.1 In `modules/home/standalone.nix`, compute the update input list (`central`, plus `private` if `nixos-central.private.enable`) once and use it for `preSwitchCommands`; verify the `ci-home-*` activation packages and `home-eval-ci-modules` are unchanged (`nix flake check`)
- [x] 1.2 Add `nixos-central-internal/home-upgrade/default.nix` (`writeShellApplication` `nixos-central-upgrade`: `--private` or no arguments, refusal while `home-manager-auto-upgrade.service` runs, lock backup/restore keyed on the `home-manager` profile link, `nix flake update … --refresh`, `home-manager switch -b backup`, the error messages from the spec) and add it to `home.packages` in `standalone.nix`; verify `shellcheck` passes on the script (via `writeShellApplication`) and `central-modules` still lists the same names
- [x] 1.3 VM test `home-upgrade-failures` in `nixos-central-internal/tests/default.nix`: lingering user, stub `home-manager-auto-upgrade` user unit, a local home flake whose stub `central` throws; cover build failure (lock and profile unchanged, "nothing was changed"), refusal during the automatic upgrade, `--private` without overlay, and an unknown argument; verify `nix build .#checks.x86_64-linux.home-upgrade-failures` passes
- [x] 1.4 README "Install on another Linux distribution": replace the manual `nix flake update … && home-manager switch …` line with `nixos-central-upgrade` (and `--private`); verify the commands match the script's usage text

## 2. `--private`

- [x] 2.1 `modules/base/upgrade.nix`: accept `--private` (`--update-input private` only; refuse with "This machine has no private overlay" when `nixos-central.private.enable` is false, before any change); usage text lists it; verify `nix flake check` evaluates the sample hosts
- [x] 2.2 Extend the `overlay-upgrades` VM test: with new commits in both stub repos, `nixos-central-upgrade --private` reports only `Updated input 'private'` and the lock's `central` revision is unchanged; extend `upgrade-failures`: `--private` on a machine without overlay fails with the message and changes nothing; verify both checks pass
- [x] 2.3 Same `--private` cases for the home command in `home-upgrade-failures` (central revision in the lock unchanged after a `--private` run that fails on the stub); verify the check passes
- [x] 2.4 README "Updates" and "Private overlay": document `nixos-central-upgrade --private` for NixOS and standalone homes; verify against the usage text

## 3. Integration

- [x] 3.1 On a real standalone home with an overlay (e.g. zbook, `--override-input central path:<checkout>` for the first run): `nixos-central-upgrade --private` after an overlay push activates it with `central` unchanged; `nixos-central-upgrade` with both updated; `systemctl --user start home-manager-auto-upgrade` still works afterwards
- [x] 3.2 `nix flake check -L` passes; `openspec validate add-home-upgrade-command --strict` passes. Done as `nix flake check --no-build` plus building every check except `reboot-notify-kde`/`-gnome` (unaffected by this change; they boot a full desktop and take 10–15 minutes each)

## Workflow follow-up

- Open a PR, merge, then archive the change (`/opsx:archive`).
