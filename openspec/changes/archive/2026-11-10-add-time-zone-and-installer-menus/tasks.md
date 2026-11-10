# Tasks

## 1. Time zone fact

- [x] 1.1 Replace the uncommitted `time.timeZone = lib.mkDefault "Europe/Zurich"` (and the now unused `lib` argument) in `modules/base/default.nix` with a new `modules/base/time-zone.nix` that sets `time.timeZone = lib.mkDefault config.nixos-central.timeZone;`. Import it from `modules/base/default.nix` and verify with `git diff modules/base/default.nix` that only the import remains.
- [x] 1.2 Add `options.nixos-central.timeZone` (str, IANA-style pattern allowing `UTC`, default `"Europe/Zurich"`) to `modules/options.nix`, and `timeZone ? "Europe/Zurich"` to `hostModules` in `nixos-central-internal/lib/default.nix`. Verify that `nix eval .#nixosConfigurations.ci-none.config.time.timeZone` prints `"Europe/Zurich"`.
- [x] 1.3 Add `timeZone = "@TIME_ZONE@"; # e.g. Europe/Zurich; list: timedatectl list-timezones` next to `keyboardLayout` in `nixos-central-internal/templates/host/flake.nix`. Verify that the template still renders to valid Nix by substituting sample values and running `nix-instantiate --parse` on the result.
- [x] 1.4 Add a `time-zone` VM check to `nixos-central-internal/tests/default.nix` with three nodes: `timeZone = "America/New_York"` reports that zone via `timedatectl show -p Timezone --value`, no fact reports `Europe/Zurich`, and `modules` setting `time.timeZone = "Asia/Tokyo"` evaluates and reports `Asia/Tokyo`. Verify with `nix build .#checks.x86_64-linux.time-zone`.
- [x] 1.5 README "How a machine is configured": add the `timeZone` row to the facts table and replace the interim time zone note with how to change `timeZone` and that machines without it use `Europe/Zurich`. Verify that the README's example matches the template line.

## 2. Prompt layer in the installer

- [x] 2.1 In `install.sh`, decide `MENUS` and `GUM` once in `preflight` (after `ensure_root`): `/dev/tty` usable, `TERM` set and not `dumb`, `NIXOS_CENTRAL_PLAIN` unset, and gum found on `PATH` or built with `nix build --no-link --print-out-paths --inputs-from "$CENTRAL" nixpkgs#gum`. If the build fails, print one info line and fall back to plain prompts. Document `NIXOS_CENTRAL_PLAIN` in `usage`. Verify by running with `TERM=dumb` and with `NIXOS_CENTRAL_PLAIN=1`, both of which must give plain prompts.
- [x] 2.2 Add the `choose`, `choose_filtered` and `confirm` helpers (design §3): gum with `</dev/tty`, ASCII-safe cursor and prefixes, and abort with "Aborted. Nothing was changed." on cancel. Their plain branches must print exactly today's texts (`Available …:`, `Choose one of: …`, `[Y/n]`/`[y/N]`). Verify with `shellcheck nixos-central-internal/installer/install.sh`.
- [x] 2.3 Switch the call sites to these helpers:
  - `choose`: keyboard layout, desktop, profile, and overlay retry/skip (plain: `(r/s) [r]`)
  - `confirm`: the NVIDIA question, password reuse, private overlay, and reboot (cancel counts as "no")

  Leave the wipe `yes`, the secrets, hostname, username, overlay URL and "Press Enter" as they are. Verify that the existing e2e prompt expectations are unchanged by running the e2e test after group 3.

## 3. Time zone in the installer

- [x] 3.1 Add `--time-zone NAME` (parse, `usage`, `TIME_ZONE_FLAG`). In `preflight`, load the zone list from `timedatectl list-timezones`, falling back to `/etc/zoneinfo`. Validate the flag before the disk is touched, failing with a message that names `timedatectl list-timezones`. Verify with the e2e failure-path phase (task 3.4).
- [x] 3.2 In `collect_machine_facts`, ask for the time zone right after the keyboard layout, with `choose_filtered` and default `Europe/Zurich` (plain: `Time zone [Europe/Zurich]: `). Pass `@TIME_ZONE@` in `write_machine_flake`, and add a `time zone` line to the `finish` summary. Verify by checking that the generated `/mnt/etc/nixos/flake.nix` in the e2e run contains `timeZone`.
- [x] 3.3 README "Install": mention the time zone question and `--time-zone`, and that the installer uses menus on the console with plain prompts on serial consoles or `NIXOS_CENTRAL_PLAIN=1`. Verify that the flag list in the README matches `--help`.
- [x] 3.4 Extend `tests/e2e/run.py`:
  - the failure-path phase: `--time-zone Bogus/Zone` aborts and `/dev/vda` stays empty
  - the prompt phase: an invalid zone is rejected, then `Europe/Lisbon` is accepted
  - the flag install: passes `--time-zone Europe/Zurich`, and the summary and installed flake show it
  - after reboot: `timedatectl show -p Timezone --value` on the installed system

  Verify with `nix run --impure -f nixos-central-internal/tests/e2e`.

## 4. Installation image

- [x] 4.1 Add `pkgs.gum` to `environment.systemPackages` and to the `start` script's `runtimeInputs` in `nixos-central-internal/iso/default.nix`. Make `start.sh`'s `ask` use `gum confirm` (default yes) when `TERM` is not `dumb` and gum is present, and keep today's `[Y/n]` prompt otherwise. Verify with `shellcheck` and with the e2e image phase, whose `[Y/n]` expectations must still pass.
- [x] 4.2 Build the image (`nix build .#iso`), boot it in QEMU with a graphical console (not serial), and on tty1 check by hand:
  - the start-up confirmations
  - the keyboard layout and desktop menus with their defaults preselected
  - typing `lisb` in the time zone filter selects `Europe/Lisbon`
  - Escape in a menu aborts with "Aborted. Nothing was changed."
  - the wipe still needs a typed `yes`

  Record the result in the PR description.

## 5. Integration

- [x] 5.1 Run `nix flake check` and the e2e test, and verify both pass. Then confirm that `openspec validate add-time-zone-and-installer-menus --strict` passes.
- [x] 5.2 Update the change's spec deltas if the implementation changed any prompt text or default from what they state. Verify by re-reading `specs/installer/spec.md` against `install.sh --help` and the prompts.

## Workflow follow-up

- Archive the change after merge (`/opsx:archive`), which syncs the `installer` and `host-configuration` deltas into the main specs.
