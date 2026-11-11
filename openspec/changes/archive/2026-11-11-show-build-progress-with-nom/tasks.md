# Tasks

## 1. Shared build helper and the NixOS upgrade

- [x] 1.1 Add `nixos-central-internal/lib/build-progress.sh` with `build_with_progress <out-link> <nix build args...>` (design §2, §3):
  - nom path when `NIXOS_CENTRAL_PLAIN` is unset, `TERM` is set and not `dumb`/`unknown`, `[ -t 2 ]`, and `nom` is on `PATH`: `nix build "$@" --out-link "$link" --log-format internal-json -v 2>&1 | nom --json`
  - otherwise: `nix build "$@" --out-link "$link"`
  - a header comment that names the copies in `install.sh` and `home-only.sh`

  Verify with `shellcheck -s bash nixos-central-internal/lib/build-progress.sh`.
- [x] 1.2 In `modules/base/upgrade.nix`:
  - inline the helper with `builtins.readFile`, and add `pkgs.nix-output-monitor` to `runtimeInputs`
  - inside the existing `if ! { ...; }` block, put `build_with_progress "$tmp/result" "/etc/nixos#nixosConfigurations.\"<hostname>\".config.system.build.toplevel"` between `nix flake update` and `nixos-rebuild switch`
  - replace the `backup` mktemp with a temp directory that holds both the lock backup and the out-link, cleaned up by the existing trap

  Verify with `nix build .#checks.x86_64-linux.upgrade-failures`: lock restored and "nothing was changed" on a build failure, refusal while an automatic upgrade runs.
- [x] 1.3 Add a VM check `build-progress` to `nixos-central-internal/tests/default.nix`. It runs a script that inlines `build-progress.sh` on an offline trivial derivation and on one that fails (`exit 1` with a marker message):
  - under `TERM=xterm script -qec ... /dev/null`, which gives a terminal: the result link exists after success; after failure the exit status is non-zero and the marker appears in the output
  - with `TERM=dumb`, and with `NIXOS_CENTRAL_PLAIN=1`: the output contains no `\x1b[` cursor-movement sequences and has the plain build log lines

  Verify with `nix build .#checks.x86_64-linux.build-progress`.

## 2. Standalone home upgrade

- [x] 2.1 In `nixos-central-internal/home-upgrade/default.nix`:
  - inline the helper and add `nix-output-monitor` to `runtimeInputs` (through `callPackage`; extend `modules/home/standalone.nix` only if the argument has to be passed explicitly)
  - before `home-manager switch`, build `"$flake#homeConfigurations.\"$USER\".activationPackage"` with `build_with_progress`
  - switch with `--flake "$flake#$USER"`, and keep the out-link in the existing temp handling

  Verify with `nix build .#checks.x86_64-linux.home-upgrade-failures` and `.#checks.x86_64-linux.home-command`, and run `shellcheck` on the generated script (`nix build` of the package, then `shellcheck result/bin/nixos-central-upgrade`).
- [x] 2.2 README, standalone home section: say that `nixos-central upgrade` shows build progress in a terminal (plain with `NIXOS_CENTRAL_PLAIN=1`), and that it uses the `homeConfigurations."<login>"` entry of the home flake. Verify that the README text matches the attribute the script builds.

## 3. NixOS installer

- [x] 3.1 In `install.sh`, add `setup_build_progress`, called in `preflight` after `setup_menus`. It sets `NOM` independently of `MENUS`:
  - `NIXOS_CENTRAL_PLAIN` unset, `TERM` not `dumb`/`unknown`, `/dev/tty` can be opened
  - `nom` found on `PATH`, or else fetched with `nixx build --no-link --print-out-paths --inputs-from "$CENTRAL" nixpkgs#nix-output-monitor`
  - on a failed fetch, one `info` line saying build progress is shown as plain output

  Verify with `shellcheck nixos-central-internal/installer/install.sh`.
- [x] 3.2 Replace the `nixos-install --flake` step in `install_system` (design §1, §4):
  - build `"/mnt/etc/nixos#nixosConfigurations.\"$HOST\".config.system.build.toplevel"` with `nixx build --store /mnt --extra-substituters 'auto?trusted=1' --out-link "$WORK/system"`
  - with `NOM` set: `--log-format internal-json -v 2>&1 | tee -a "$LOG" | "$NOM" --json >/dev/tty 2>&1`; otherwise a plain build
  - then `nixos-install --root /mnt --system "$(readlink "$WORK/system")" --no-root-passwd --no-channel-copy`

  Keep the copy of the helper commented as a copy of `lib/build-progress.sh`. Verify with `nix run --impure -f nixos-central-internal/tests/e2e`, which runs the plain path: the installed VM boots and the later phases pass.
- [x] 3.3 Add `pkgs.nix-output-monitor` to `environment.systemPackages` in `nixos-central-internal/iso/default.nix`, next to gum. Update the comment. Verify with `nix build .#packages.x86_64-linux.iso`, and check that `nom` is in the image's system path (`nix path-info -r` of the ISO's toplevel contains `nix-output-monitor`).
- [x] 3.4 Check the nom path by hand: boot the ISO in QEMU with a graphical console (or install in a VM from the console), and confirm three things:
  - the live display is shown during "installing NixOS"
  - `/tmp/nixos-central-install.log` holds `@nix {` JSON lines and no `\x1b[` cursor-movement sequences
  - an install with a deliberately broken configuration (e.g. `NIXOS_CENTRAL_FLAKE` pointing to a branch with an evaluation error) shows the error and the `on_error` message

  Note the result in the PR.
- [x] 3.5 README "Install": a sentence that the installation step shows live build progress on the console, plain on serial consoles or with `NIXOS_CENTRAL_PLAIN=1`, and that the log then contains Nix's JSON log lines. Verify that `usage` in `install.sh` describes `NIXOS_CENTRAL_PLAIN` the same way.

- [x] 3.6 Fix the nom errors (`DerivationReadError … openFile: does not exist`) seen in the manual install (3.4). `build_into_target` in `install.sh` writes the build plan into the live store (`nix eval --raw "<installable>.drvPath"`) before building into `/mnt`, only when nom is used (design §4). Extend the `build-progress` VM test to run `install.sh`'s functions against a separate store: the control subtest without the step shows `DerivationReadError`, and the fixed path shows none and writes `@nix {` lines without redraws to the install log. Verify with `nix build .#checks.x86_64-linux.build-progress` and a new e2e run (plain path).

## 4. Home installer

- [x] 4.1 In `home-only.sh`:
  - add a copy of the helper with the fetch-or-plain logic from 3.1 (`[ -t 2 ]`; nom from `PATH`, or fetched with `--inputs-from "$CENTRAL"`)
  - in `activate_home`, build `"$HM_DIR#homeConfigurations.\"$USERNAME\".activationPackage"` with it, then keep the existing `home-manager switch ... -b backup` and its `die` message

  Verify with `shellcheck nixos-central-internal/installer/home-only.sh`.
- [x] 4.2 Run `home-only.sh` from the working tree in a non-NixOS container or VM (e.g. Ubuntu with Nix installed), once in a terminal and once with `TERM=dumb`. Confirm the live display in the first run, plain output in the second, and that both activate the home. Note the result in the PR.

## 5. Integration

- [x] 5.1 Run `nix flake check` and `nix run --impure -f nixos-central-internal/tests/e2e`. Both must pass, including the e2e `nixos-central upgrade` phase on the plain path.
- [x] 5.2 On a real machine, run `nixos-central upgrade` from a terminal after a central commit, and confirm the live display, activation, and the reboot hint at the end.

## Workflow follow-up

- Archive the change after review and merge, then check that `openspec/specs/build-progress/spec.md` exists with its Purpose.
