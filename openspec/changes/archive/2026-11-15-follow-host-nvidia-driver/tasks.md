# Tasks

## 1. Pin-sync script

- [x] 1.1 Add `nixos-central-internal/home-upgrade/nvidia-pin.nix`, a `writeShellApplication` `nixos-central-nvidia-pin <flake-dir>` (design: "Read the pin from the line", "Where the host version comes from", "Download URL", "Shape of the script"):
  - reads the host version from `${NIXOS_CENTRAL_NVIDIA_VERSION_FILE:-/proc/driver/nvidia/version}`, parsed with the installer's pattern; it is silent when the file is missing
  - finds exactly one `nvidia = null;` or `nvidia = { version = "…"; sha256 = "…"; };` line in `<flake-dir>/flake.nix`. On `null` it is silent. Any other shape gets a warning, but only when a host driver is loaded and there is something to update
  - if the versions are equal, it exits without network access
  - otherwise it runs `nix store prefetch-file --json` on `${NIXOS_CENTRAL_NVIDIA_BASE_URL:-https://download.nvidia.com/XFree86}/Linux-<arch>/<v>/NVIDIA-Linux-<arch>-<v>.run`, then rewrites only the two quoted values in place and prints `NVIDIA driver <old> -> <new>`
  - on a fetch failure it prints a warning naming the version and leaves the file untouched
  - always exits 0

  Verify with `shellcheck` on the built script.
- [x] 1.2 Add a `nvidia-pin` check (`runCommand`, no VM) to `nixos-central-internal/tests/default.nix`. It uses fake version files, fake flakes and a stub `nix` on `PATH` that prints a fixed hash JSON, or fails when a marker file is present or when it is called unexpectedly. It covers every "NVIDIA pin follows the host driver" scenario:
  - changed: line rewritten, comment and indentation kept, `cmp` against the expected file
  - unchanged: stub not called, file byte-identical
  - `null`, even with a driver loaded
  - no version file
  - fetch fails: warning, file unchanged
  - other shape (two lines, or a reformatted line): warning, file unchanged
  - exit status 0 in all cases

  Verify with `nix build .#checks.x86_64-linux.nvidia-pin`.

## 2. Upgrade paths

- [x] 2.1 In `nixos-central-internal/home-upgrade/default.nix`:
  - take the pin package as an argument and run it on `$flake` before `nix flake update`
  - back up `flake.nix` next to the lock
  - on a failure with an unchanged profile, restore `flake.nix` if it differs (`cmp -s`) along with the lock
  - wire the argument through `modules/home/standalone.nix`

  Verify with `nix build .#checks.x86_64-linux.home-upgrade-failures` (existing subtests still pass).
- [x] 2.2 Extend `home-upgrade-failures` with a subtest. The `~/home` flake gets a template-shaped `nvidia = { version = "100.10.10"; sha256 = "…"; };` line (the version must match `NNN.NN[.NN]`). A fake `.run` file goes under a `file://` base URL; set `NIXOS_CENTRAL_NVIDIA_VERSION_FILE` and `NIXOS_CENTRAL_NVIDIA_BASE_URL` to `100.20.20`. The subtest runs `home-upgrade`, which fails at the stub central, and asserts that the output shows the pin was updated, then "nothing was changed", and that `flake.nix` and `flake.lock` are byte-identical to before. Verify with `nix build .#checks.x86_64-linux.home-upgrade-failures`.
- [x] 2.3 In `modules/home/standalone.nix`, prepend `"${nvidia-pin}/bin/nixos-central-nvidia-pin ."` to `services.home-manager.autoUpgrade.preSwitchCommands`. Verify with `nix eval` of a CI home's `systemd.user.services.home-manager-auto-upgrade` script path, and `grep` the built script for the pin command before `nix flake update`.

## 3. GPU setup after the switch

- [x] 3.1 In `nixos-central-internal/home-upgrade/default.nix`, after a successful switch:
  - `nix eval --raw` the home's `config.targets.genericLinux.gpu` with `--apply` to `"<drivers> <setup-exe>"`, or `""` when disabled
  - compare `<drivers>` with `readlink /run/opengl-driver`
  - on a difference with `[ -t 0 ] && [ -t 1 ]`, run `sudo <setup-exe>`; on its failure, print `sudo <setup-exe>` as a later step
  - without a terminal, print the command
  - the exit status stays 0 once the switch succeeded

  Verify with `shellcheck` on the built `nixos-central-upgrade`, and by evaluating the `--apply` expression against a CI home (`nix eval .#…ciHome…`), which prints two store paths.
- [x] 3.2 Update `README.md` "GPU drivers": the upgrade keeps the recorded NVIDIA version in step with the host and offers the sudo setup when the drivers change. After the distribution updates the driver, run `nixos-central upgrade`, which replaces the advice to rerun the installer with `--replace-existing`. Verify by reading the rendered section.

## 4. Integration

- [x] 4.1 Run `nix flake check` (or the CI-equivalent per-check builds) and confirm all checks pass.
- [x] 4.2 Manual check on an NVIDIA standalone host (this machine): set the local pin back to the previous version and run the new `nixos-central upgrade` from a terminal. The pin moves to the loaded version, sudo is offered once, `readlink /run/opengl-driver/etc` shows the loaded version, and Zed starts with the GPU. A second run prints no GPU setup.

## Workflow follow-up

- Archive the change (`/opsx:archive`) after review, and commit it as `chore(openspec): archive follow-host-nvidia-driver`, as earlier changes were.
