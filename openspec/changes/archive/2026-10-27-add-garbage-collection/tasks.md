# Tasks

## 1. System garbage collection (NixOS)

- [x] 1.1 Add `modules/base/gc.nix` with options `nixos-central.gc.enable` (default true), `keepDays` (default 30), `dates` (default `weekly`), the `nixos-central-gc` script (select generations as `--delete-older-than` would, minus current, booted and running; delete them; `nix-collect-garbage`; rewrite the boot menu via the profile's `switch-to-configuration boot` only if something was deleted), and a persistent, randomized, low-priority service + timer; import it from `modules/base/default.nix`. Verify `nix flake check --no-build` passes and the timer unit is in `ci-none`'s configuration.
- [x] 1.2 Set `nix.settings.min-free` (2 GiB) and `max-free` (10 GiB) as `lib.mkDefault` in the same module; verify with `nix eval` on `ci-none`'s `nix.settings`.
- [x] 1.3 Add a VM test `gc` in `nixos-central-internal/tests/default.nix`: backdated system generations (45, 35, 20 days, current 2 days) → 45 deleted, 35 kept (active at cutoff), 20 and current kept, its unreferenced store path gone, boot menu entries updated and default unchanged; a running generation 50 days old with staged 45 and 1 day old ones → 50 kept; `nixos-central.gc.enable = false` → no timer. Verify with `nix build .#checks.x86_64-linux.gc`.

## 2. Home garbage collection

- [x] 2.1 Add `modules/home/gc.nix` enabling home-manager `nix.gc` (`automatic`, `dates = "weekly"`, `persistent = true`, `options = "--delete-older-than 30d"`, all overridable defaults); add it to `sharedModules` in `modules/user.nix`, to `mkHome`, and to the internal list in `nixos-central-internal/lib/overlay.nix`. Verify `nix flake check --no-build` passes (incl. the `central-modules` check) and the `nix-gc` user timer is in the `ci-home-default` home and in alice's home on `ci-none`.
- [x] 2.2 Extend the `gc` VM test: alice's personal profile generations (`nix-env -p` her default profile, backdated 70, 60, 40, current 3 days) → running alice's `nix-gc` user service deletes the 70- and 60-day ones, keeps the 40-day one (active at the cutoff) and the current one, without root. Verify with `nix build .#checks.x86_64-linux.gc`.
- [x] 2.3 Check a profile override evaluates: `nix.gc.options = "--delete-older-than 90d"` via `extendModules` on `ci-home-default` yields that option in the service; verify with `nix eval`.

## 3. Documentation

- [x] 3.1 README: in "Updates", the weekly cleanup (30 days kept, what that means for the boot menu and `--rollback`, how to change or turn it off); in "Install on another Linux distribution", that homes clean up their own generations weekly and `home-manager generations` shows only the last 30 days. Verify the option names match the modules.

## Workflow follow-up

- Archive the change after review and merge.
