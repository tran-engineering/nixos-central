# Tasks

VM tests (`runTest`) time out locally without KVM; build them in CI. `update-notice-script` is a plain derivation and can be built locally with `nix build .#checks.x86_64-linux.update-notice-script`.

## 1. NixOS: stop the daily upgrade

- [x] 1.1 Delete `modules/base/auto-upgrade.nix`, drop it from `modules/base/default.nix`, and update the comments in `modules/base/central-update-inputs.nix`, `modules/base/flatpak.nix` and the header of `modules/base/upgrade.nix` that refer to it; verify `nix eval .#nixosConfigurations.<ci-host>.config.systemd.timers --apply builtins.attrNames` lists no `nixos-upgrade`
- [x] 1.2 Remove the "automatic upgrade is running" check from `modules/base/upgrade.nix` (keep the stamp touch); verify `nix flake check --no-build` evaluates
- [x] 1.3 In `nixos-central-internal/tests/default.nix`, drop the auto-upgrade-running case and fake `nixos-upgrade` service from `upgrade-failures`, assert `nixos-upgrade.timer` does not exist, and change `overlay-upgrades`' key-revoked case to run `nixos-central upgrade` and assert lock file and system profile are unchanged; verify both checks pass in CI
- [x] 1.4 In `nixos-central-internal/tests/e2e/run.py`, remove the "auto-upgrade: central change … staged for next boot" step (and any `nixos-upgrade.timer` stop calls that no longer apply, e.g. `tests/default.nix:641`); verify the script still parses (`python3 -m py_compile`)

## 2. Standalone homes: stop the daily upgrade, record `nixos-central upgrade`

- [x] 2.1 In `modules/home/standalone.nix`, remove `services.home-manager.autoUpgrade` and the `home-manager-auto-upgrade` `ExecStartPost`; pass `flakeDir = "${config.xdg.configHome}/home-manager"`, `switchFlags = [ "-b" "backup" ]` and `stamp = config.nixos-central.updateNotice.stamp` to `home-upgrade`; update the `HM_DIR` comment in `nixos-central-internal/installer/home-only.sh` and the comment in `nixos-central-internal/home-upgrade/nvidia-pin.nix`; verify the `mkHome` CI home evaluates and has no `home-manager-auto-upgrade` user timer
- [x] 2.2 In `nixos-central-internal/home-upgrade/default.nix`, drop the running-service check and touch the stamp (creating its directory) after a successful switch; verify with the home-upgrade test that an upgrade without changes updates the stamp's mtime
- [x] 2.3 Update `home-upgrade-failures` in `nixos-central-internal/tests/default.nix`: remove the auto-upgrade-running case and fake service, assert no `home-manager-auto-upgrade.timer` exists for the user; verify in CI
- [x] 2.4 Update the home installer summary in `nixos-central-internal/installer/home-only.sh`: replace "updates daily, automatically (systemctl --user list-timers …)" with how to update (`nixos-central upgrade`); verify the home-installer test's summary assertions match

## 3. Update notice: 1-day default, upgrade command in the hint

- [x] 3.1 In `modules/home/update-notice.nix`, change the `days` default to `1` and its description; set the hint to `Update with: nixos-central upgrade` on NixOS and standalone homes, and the staged-generation hint to `An update is installed; reboot to use it (or update again with: nixos-central upgrade).`; update the file's header comment (no auto-upgrade); verify `update-notice-script` builds locally after 3.2
- [x] 3.2 Update `update-notice-script` in `nixos-central-internal/tests/default.nix`: new hint text; add cases for the default threshold (stamp 2 days old prints, 20 hours old is quiet with `NIXOS_CENTRAL_NOTICE_DAYS` unset) and assert output never contains `auto-upgrade`; verify `nix build .#checks.x86_64-linux.update-notice-script`
- [x] 3.3 Update the NixOS `update-notice` VM test: replace `"Run nixos-central upgrade"` with the new hint, keep the reboot case, and check the default threshold; verify in CI

## 4. Documentation

- [x] 4.1 Update `README.md`: intro ("follows this repository automatically"), install step 5 and "Private overlay" (passphrase-less key: upgrades run as root, not "daily updates"; failure shown by `nixos-central upgrade`, not `systemctl status nixos-upgrade`), standalone home section (no daily update), NVIDIA section (drop daily-update sentences), and "Updates" (no daily staging, no `systemctl start nixos-upgrade`; updates only with `nixos-central upgrade`; notice after 1 day showing the command); verify `grep -nE 'nixos-upgrade|auto-upgrade|daily update|updates itself' README.md` only matches Flatpak/fwupd text
- [x] 4.2 Update the Purpose lines of `openspec/specs/system-updates/spec.md` and `openspec/specs/stale-update-notice/spec.md` so they no longer describe automatic updates; verify `openspec validate --specs --strict` passes

## 5. Integration

- [ ] 5.1 Run `grep -rnE 'nixos-upgrade|home-manager-auto-upgrade|autoUpgrade' modules nixos-central-internal` and verify no references remain outside intentional test assertions of their absence; run `nix flake check` in CI and verify all checks pass

## Workflow follow-up

- Archive the change with `/opsx:archive` after review and CI are green.
