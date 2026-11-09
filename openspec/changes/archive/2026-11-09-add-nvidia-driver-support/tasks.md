# Tasks

## 1. The `nvidia` machine fact

- [x] 1.1 Add `nixos-central.nvidia` to `modules/options.nix` as `nullOr` a submodule with `channel` (enum `stable`, `unstable`; default `stable`) and optional `intelBusId`, `amdgpuBusId` and `nvidiaBusId` matching `PCI:<bus>@<domain>:<device>:<function>` (design D1). Verify `nix eval .#nixosConfigurations.ci-kde.config.nixos-central.nvidia` is `null`.
- [x] 1.2 Add `nvidia ? null` to `hostModules` in `nixos-central-internal/lib/default.nix` and pass it into `nixos-central`. Add the `nvidia = @NVIDIA@;` line with a comment on its values to `templates/host/flake.nix`, before `modules = [`. Verify `nix build .#checks.x86_64-linux.private-flake-edit` still passes, and `ci-kde`'s `system.build.toplevel` has the same `drvPath` as before this change.

## 2. Driver policy

- [x] 2.1 Add `modules/base/nvidia.nix` and import it in `modules/base/default.nix`: video driver, open modules and power management (design D2). Verify with the new `nvidia-eval` flake check, built on `ciHost` like `host-profile`: with `nvidia = { }` on all four desktops the open module is in `boot.extraModulePackages` and `nouveau` is blacklisted; with `nvidia = null` no NVIDIA driver is configured.
- [x] 2.2 Add PRIME offload, `nvidia-offload` and fine-grained power management for facts with bus IDs, plus the assertion on bus ID combinations. Extend `nvidia-eval`: Intel and AMD facts enable offload and fine-grained power management; `{ }` enables neither; a lone `nvidiaBusId` and Intel plus AMD together fail evaluation (`tryEval`). Verify `nix build .#checks.x86_64-linux.nvidia-eval` passes.
- [x] 2.3 Enable `hardware.nvidia-container-toolkit` with the fact. Extend `nvidia-eval`: with the fact Docker's `features.cdi` is on and the toolkit is enabled; with `null` it's disabled. Verify the check passes.
- [x] 2.4 README: add an "NVIDIA" section covering the fact, adding it to an existing machine by hand, `nvidia-offload`, and containers using `--device nvidia.com/gpu=all` rather than `--gpus` or `runtime: nvidia`. Verify every command and example in the section against the options evaluated above.

## 3. Driver channels and build checks

- [x] 3.1 Implement `channel = "unstable"` through `config.boot.kernelPackages.callPackage` on the unstable input's driver definition, using its `latest` branch (design D3). Extend `nvidia-eval`: the unstable package's version equals `pkgs.unstable.linuxPackages.nvidiaPackages.latest.version`, stable's equals `pkgs.linuxPackages.nvidiaPackages.production.version`, the open module's name carries the system kernel's version, and an unknown channel fails evaluation. Verify the check passes.
- [x] 3.2 Add `nvidia-driver-stable` and `nvidia-driver-unstable` flake checks that build `hardware.nvidia.package` and the open module for each channel (design D6). Verify both with `nix build .#checks.x86_64-linux.nvidia-driver-stable .#checks.x86_64-linux.nvidia-driver-unstable`, and that `modinfo -F license` on the built `nvidia.ko` reports `Dual MIT/GPL`.
- [x] 3.3 README: describe the channels, what each costs in local builds, and that an update waits for both channels' builds. Add the two checks to the comment on `nix flake check` in `.github/workflows/flake-update.yml` if the comment no longer covers them. Verify the README's example `channel` line against the option.

## 4. GPU detection

- [x] 4.1 Add `nixos-central-internal/installer/detect-nvidia.sh`, taking the sysfs root and printing `null`, `{ }` or a set with bus IDs (design D4); expose it as `lib.nvidiaDetect`, and add it to shellcheck in `.github/workflows/ci.yml`. Verify `shellcheck` passes, and that on this laptop it prints `{ intelBusId = "PCI:0@0:2:0"; nvidiaBusId = "PCI:1@0:0:0"; }`.
- [x] 4.2 Add the `nvidia-detect` check running the script against fake sysfs trees, covering every scenario of the installer spec's "Installer records PRIME only for hybrid laptops", no NVIDIA GPU, and a 3D controller (class `0x0302`) as the NVIDIA GPU. Verify `nix build .#checks.x86_64-linux.nvidia-detect` passes.

## 5. Installer

- [x] 5.1 Parse `--nvidia` and `--no-nvidia` and reject both together in `check_flags`; add them to `usage` and the README's options table. Verify with new e2e steps: `--nvidia --no-nvidia` exits before changing a disk, and `--nvidia` in the VM, which has no NVIDIA GPU, explains this and exits before changing a disk.
- [x] 5.2 In `collect_machine_facts`, after the desktop question, run detection, then the confirmation prompt with the Turing note and the flag handling. Substitute `@NVIDIA@` in `write_machine_flake` (design D4). Verify with the e2e test: the machine flake has `nvidia = null;`, no NVIDIA question was asked and the installed system builds.
- [x] 5.3 Check `download.nvidia.com` when NVIDIA is selected, aborting with the actionable message (design D5). Verify the check is skipped in the e2e run with no NVIDIA GPU, and on real hardware that the message appears with the host blocked, for example with an `/etc/hosts` entry on the live image, and that no disk has changed.
- [x] 5.4 Add the NVIDIA line to the `finish` summary, and update "What the installer does" in the README. Verify on this laptop's install (task 7.2) that the summary says PRIME offload.

## 6. Upgrade reboot hint

- [x] 6.1 In `modules/base/upgrade.nix`, compare the `kernel-modules` links of `/run/booted-system` and `/run/current-system` when the kernels match, and print the driver hint (design D7). Add a VM check, alongside the upgrade tests in `nixos-central-internal/tests/default.nix`, that runs the hint against stand-in generations, because the offline VM can't build a real one: with replaced kernel modules the driver hint appears, with a replaced kernel only the kernel hint, and with no change no hint. Verify the check passes.

## 7. Integration and hardware verification

- [x] 7.1 Run `nix flake check` and the installer e2e test (`nix run --impure -f nixos-central-internal/tests/e2e`). Both pass.
- [ ] 7.2 Back up this laptop, then install from an image of the branch with `NIXOS_CENTRAL_FLAKE` set. Verify the installer shows the Intel and NVIDIA GPUs, the summary says PRIME offload, and the machine reaches GDM and logs in to a Wayland session.
- [x] 7.3 On this laptop verify: `nvidia-offload glxinfo` reports the NVIDIA GPU while a plain `glxinfo` reports Intel; suspend and resume keep the session; `/sys/bus/pci/devices/0000:01:00.0/power/runtime_status` is `suspended` when idle, including after the CDI generator has run and after a container has exited; `docker run --rm --device nvidia.com/gpu=all <image> nvidia-smi` lists the GPU. Record any failures and resolve them centrally in `modules/base/nvidia.nix`.
- [x] 7.4 No NVIDIA desktop is available for testing, so the desktop path is verified without hardware: `nvidia-detect` records `nvidia = { }` for a desktop with an enabled iGPU and for one with a wireless mouse's battery, and `nvidia-eval` shows no PRIME, offload command or fine-grained power management for that fact. Verify both checks pass.
- [x] 7.5 On one machine, set `channel = "unstable"`, rebuild, and verify after reboot that `nvidia-smi` reports the unstable driver's version and the session works. Switch back with `channel = "stable"`, and verify the same.

## Workflow follow-up

- State in the PR that NVIDIA desktops have not been tested on real hardware: GDM and the session on a display attached to the NVIDIA GPU, and containers there, remain unverified.
- Archive the change after review and hardware verification.
