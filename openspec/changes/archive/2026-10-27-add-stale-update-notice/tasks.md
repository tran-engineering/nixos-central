# Tasks

## 1. Recording successful updates

- [x] 1.1 Touch `/var/lib/nixos-central/last-update` after a successful `nixos-upgrade` run (`postStart` in `modules/base/auto-upgrade.nix`) and at the end of a successful `nixos-central-upgrade`; verify `nix flake check --no-build` evaluates and the generated unit has the `ExecStartPost`.
- [x] 1.2 Add `ExecStartPost` to the `home-manager-auto-upgrade` user service in `modules/home/standalone.nix` touching `${config.xdg.stateHome}/nixos-central/last-update`; verify the generated unit file of the `_default` CI home contains it.

## 2. Notice script and module

- [x] 2.1 Add `modules/home/update-notice.nix` with options `nixos-central.updateNotice.days` (default 7, `0` = off) and internal `nixos-central.updateNotice.standalone`, and the `nixos-central-update-notice` script (last successful update = later of stamp and newest generation; running configuration age; central revision age; staged check; hints; silent when within threshold or unknown; env overrides for tests). Verify by running the built script against fake state with old and recent dates.
- [x] 2.2 Hook the script into the enabled shells (`programs.bash.initExtra`, `programs.fish.interactiveShellInit`, `programs.zsh.initContent`) when `days > 0`, errors suppressed; add the module to `sharedModules` in `modules/user.nix` and to `mkHome`; set `standalone = true` in `standalone.nix`. Verify the generated `.bashrc` of the `_default` home and fish/zsh config of the `ci-modules` home contain the call, and `nix flake check --no-build` passes.

## 3. Tests

- [x] 3.1 Add a check running the script against fake standalone state: stale → notice with all three ages and the home-manager hint; recent stamp with old generation and old central revision → no output; recent generation with old stamp → no output; missing lock file → central age left out, no stderr; no stamp and no profile → no output. Verify with `nix build .#checks.x86_64-linux.update-notice-script`.
- [x] 3.2 Add a VM test (NixOS, user alice): with a backdated system generation and no stamp, `bash -i` as alice prints the notice with the `nixos-central-upgrade` hint; with a staged newer fake generation the hint says reboot; after touching the stamp, no notice; `bash -c true` prints nothing. Verify with `nix build .#checks.x86_64-linux.update-notice`.

## 4. Documentation

- [x] 4.1 Document the notice in README "Updates" (when it appears, the three ages, default 7 days, `nixos-central.updateNotice.days` in a profile, `0` to turn off); verify the option name matches the module.

## Workflow follow-up

- Archive the change after review and merge.
