# Tasks

## 1. NixOS command

- [x] 1.1 Add `nixos-central-internal/diff/default.nix` (`writeShellApplication` `nixos-central-diff`, `runtimeInputs` `dix` and `coreutils`, `mode` argument): usage and exit 2 on any argument; system mode compares current → staged when they differ, else previous → newest generation, using the highest existing link number below the newest; "No earlier generation to compare with." and exit 0 when there is none; headers as in design.md. Verify that `shellcheck` passes (via `writeShellApplication`) and `nix flake check --no-build` evaluates
- [x] 1.2 Add `modules/base/diff.nix` (package with `mode = "system"` in `environment.systemPackages`) and import it in `modules/base/default.nix`; verify `nixos-central-diff` is in the `ci-none` closure (`nix build .#nixosConfigurations.ci-none.config.system.build.toplevel` and `ls result/sw/bin`)
- [x] 1.3 VM test `diff` in `nixos-central-internal/tests/default.nix` (desktop `none`). Two fake generations built as `buildEnv`s, one with `hello` and one with `hello` + `jq`, via `additionalPaths`. As alice, cover: only one generation (message, exit 0); staged update (`nix-env -p … --set`, output says "Pending" and lists `jq`); update already in use (set the profile to a fake generation, then back to the running system, so newest = current; output names both generation numbers); a GC'd gap (delete the middle link, previous is the next lower one); unknown argument (exit 2). Verify `nix build .#checks.x86_64-linux.diff` passes
- [x] 1.4 README "Updates": document `nixos-central-diff` next to the notification and `nixos-central-upgrade` bullets; verify the text matches the command's headers and usage

## 2. Reboot notification

- [x] 2.1 `modules/base/reboot-notify.nix`: change the body to mention `nixos-central-diff` (title unchanged); update the README quote of the notification if it shows the body. Verify `nix build .#checks.x86_64-linux.reboot-notify-kde` still passes, and extend its "staged update notifies once" subtest to check the body in the journal or the notification server, if that is feasible without flakiness; otherwise just check `notify-send`'s arguments in the script
- [x] 2.2 Gate `modules/base/reboot-notify.nix` by an internal option `nixos-central.rebootNotify.enable` (default `desktop != "none"`); add `checks.reboot-notify`: `desktop = "none"` with the option on, a lingering user and a Gio stub notification server that logs title and body; same subtests as the desktop tests, plus the body names `nixos-central-diff`. Verify `nix build .#checks.x86_64-linux.reboot-notify` passes and `host-ci-none` has no `nixos-central-reboot-notify` unit
- [x] 2.3 Move `reboot-notify-kde`/`-gnome` from `checks` to `legacyPackages.x86_64-linux.desktopTests`; README "Development" says how to run them. Verify `nix flake check --no-build` no longer lists them and `nix build .#desktopTests.reboot-notify-kde` still passes

## 3. Standalone homes

- [x] 3.1 `modules/home/standalone.nix`: add the package with `mode = "home"` (profile `~/.local/state/nix/profiles/home-manager`) to `home.packages`; verify the `ci-home-default` activation package contains `bin/nixos-central-diff` and `central-modules` still lists the same names
- [x] 3.2 VM test `home-diff`: lingering user with the home-mode package, two fake home generations set with `nix-env -p ~/.local/state/nix/profiles/home-manager --set`; cover one generation (message, exit 0), two generations (lists `jq`, both numbers), unknown argument. Verify `nix build .#checks.x86_64-linux.home-diff` passes
- [x] 3.3 README "Install on another Linux distribution": add `nixos-central-diff` next to the `nixos-central-upgrade` lines; verify against the usage text

## 4. Integration

- [ ] 4.1 On a real NixOS machine (`--override-input central path:<checkout>`): after `sudo systemctl start nixos-upgrade`, `nixos-central-diff` shows the pending changes; after a reboot it shows the last update's changes. On a standalone home, after `nixos-central-upgrade`, it shows the changes
- [x] 4.2 `nix flake check -L` passes; `openspec validate add-generation-diff-command --strict` passes

## Workflow follow-up

- Open a PR, merge, then archive the change (`/opsx:archive`).
