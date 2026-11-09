# Design

## Context

See `proposal.md` for motivation and `specs/` for required behavior.

Machine facts already flow one way: the installer substitutes placeholders in `templates/host/flake.nix`, the machine flake passes them to `mkHost`, `hostModules` copies them into `nixos-central.*` (`modules/options.nix`), and modules under `modules/base` act on them.

Evaluating the pinned flake showed:

- `hardware.nvidia.open` has no usable default on these drivers. Leaving it unset fails evaluation.
- Stable's driver channels are 595.x (`production`, `latest`: 595.71.05). Unstable has `production` 595.112.07 and `latest` 615.78.08.
- `pkgs.unstable.linuxPackages.kernel` differs from the system kernel by store path, even though both are version 6.18.60.
- Open modules, power management and the container toolkit evaluate with no failed assertions in these samples: Intel PRIME offload with fine-grained power management on KDE, niri-noctalia and `none`; the AMD equivalent on GNOME; no PRIME on KDE and `none`. The unstable driver was evaluated with the open modules on KDE, with no failed assertions. Task 2 extends this to every desktop. Nothing has been built or booted on NVIDIA hardware.
- For the current lock, `cache.nixos.org` has stable's `nvidia-open`, but not `nvidia-x11` on either channel, and not the unstable `nvidia-open` built against the system kernel.

The hardware this has to work on is at least this laptop: Intel Alder Lake-P plus RTX A2000 (GA107), at `00:02.0` and `01:00.0`, currently in Ubuntu's on-demand mode.

## Goals / Non-Goals

**Goals:**

- A single `nvidia` fact, with all driver policy central, so changing the policy reaches machines through normal updates.
- Detection that can be tested without NVIDIA hardware.

**Non-Goals:**

- Identifying GPU generations. Every machine in scope has a Turing or newer GPU; the installer states the requirement and `--no-nvidia` is the way out.
- Detecting the channel or asking about it during installation.
- Changing the installation image. Everything the installer needs comes from sysfs and the existing network tools.

## Decisions

### D1: Fact shape

```nix
nvidia = null;                          # no NVIDIA driver
nvidia = { };                           # NVIDIA, no PRIME
nvidia = { channel = "unstable"; };     # newer driver
nvidia = {                              # hybrid laptop
  intelBusId = "PCI:0@0:2:0";           # or amdgpuBusId
  nvidiaBusId = "PCI:1@0:0:0";
};
```

`nixos-central.nvidia` is `nullOr (submodule ...)`, with `channel` as an enum defaulting to `"stable"` and bus IDs as optional strings matching `PCI:<bus>@<domain>:<device>:<function>`. The name matches the existing `mkHome` argument, though the contents differ: `mkHome` records a host driver's version and hash, while `mkHost` selects a driver. The fact records hardware and a channel choice, not the PRIME mode or power settings, which stay central.

*Alternatives:* `nvidia = "open"` plus separate top-level bus ID arguments spreads one concept over several `mkHost` arguments. Generating `hardware.nvidia.*` directly into the machine flake would freeze policy on each machine at install time and conflict with the thin flake requirement.

### D2: A central module holds the policy

New `modules/base/nvidia.nix`, active when the fact is not `null`:

- `services.xserver.videoDrivers = [ "nvidia" ]` and `hardware.nvidia.open = true`
- `hardware.nvidia.powerManagement.enable = true`
- `hardware.nvidia-container-toolkit.enable = true`; `modules/base/docker.nix` already enables Docker everywhere, and the toolkit module turns on Docker's CDI feature
- with bus IDs: `prime.offload.enable`, `prime.offload.enableOffloadCmd`, the bus IDs and `powerManagement.finegrained = true`
- an assertion that bus IDs are either absent or exactly `nvidiaBusId` with one of `intelBusId` and `amdgpuBusId`

Fine-grained power management is on for every hybrid machine, because battery life is why these laptops use offload in the first place.

*Alternative:* a separate `modules/nvidia.nix` next to `desktops.nix`. `modules/base` already holds optional features such as `u2f.nix` and `graphical.nix`, so it fits there.

### D3: Unstable driver built against the system kernel

```nix
unstableDrivers = config.boot.kernelPackages.callPackage
  "${inputs.nixpkgs-unstable}/pkgs/os-specific/linux/nvidia-x11/default.nix" { };
hardware.nvidia.package = unstableDrivers.latest;
```

Modules must be built against the kernel that loads them. This takes the driver's definition from unstable and its kernel and libraries from the system's nixpkgs. The stable channel leaves `hardware.nvidia.package` at the module's default, which stays cached and doesn't evaluate the unstable input.

`"unstable"` means `latest` because unstable's `production` is still the same 595 major as stable, which wouldn't justify a local kernel module build on each machine.

*Alternatives:* `pkgs.unstable.linuxPackages.nvidiaPackages.latest` is built against a kernel at a different store path, even when the versions match, so it can't be relied on to load. Moving the machine to unstable's kernel would make the whole system depend on an unstable package set.

### D4: Detection as a separate script with one output

New `nixos-central-internal/installer/detect-nvidia.sh`, published as `lib.nvidiaDetect` and fetched by the installer the same way as `lib.privateFlakeEdit`. Its single argument is the sysfs root, defaulting to `/sys`. It prints the value for the machine flake: `null`, `{ }` or a set with bus IDs.

- GPUs: `bus/pci/devices/*` where `class` starts with `0x03`, and `vendor` is `0x10de` (NVIDIA), `0x8086` (Intel) or `0x1002` (AMD).
- Battery: `class/power_supply/*` with `type` = `Battery` and a `scope` other than `Device`, because peripherals report `scope` = `Device`.
- Bus IDs: PCI addresses are hexadecimal, and each field is converted to decimal.

If there's more than one NVIDIA GPU, or an Intel and an AMD one, the first in PCI order is used, Intel before AMD. Sysfs needs no extra tools, whichever image the installer runs from.

The flag and prompt logic stays in `install.sh`, in `collect_machine_facts` after the desktop question, which comes before the disk is touched. `--nvidia` and `--no-nvidia` set state in `parse_flags`, and their conflict is rejected in `check_flags`. The template gets `nvidia = @NVIDIA@;`. It goes before the `modules = [` line, which `flake-edit.sh` uses as its anchor and which stays unique.

*Alternatives:* `lspci` output is meant for people, and sysfs avoids depending on the image's packages. Keeping the function inside `install.sh` would make it untestable, because the script is a single file with `main` on its last line.

### D5: Reachability check after the driver is selected

The check runs right after the NVIDIA answer in `collect_machine_facts`, using `curl -sI --max-time 15 https://download.nvidia.com/` and treating any HTTP response as reachable, because the site root's status code isn't what matters. It sits there rather than in `preflight`, which runs before the answer is known.

### D6: Build checks for drivers, evaluation checks for policy

Two new kinds of flake check:

- `nvidia-eval`: forces `system.build.toplevel` evaluation for sample hosts across desktops, facts and channels, asserts on the resulting options, and uses `tryEval` for invalid facts. No build, so it's cheap.
- `nvidia-driver-stable` and `nvidia-driver-unstable`: build `hardware.nvidia.package` and the open module only, joined with `linkFarm`.

These go into `checks`, not `nixosConfigurations`, because every `nixosConfigurations` entry is built in full on each push. The flake update workflow runs `nix flake check` before merging, so a broken driver stops the lock update.

A third check, `nvidia-detect`, runs the script against fake sysfs trees, in the style of `private-flake-edit`.

### D7: Reboot hint compares kernel modules

`upgrade.nix` already compares the kernels of `/run/booted-system` and `/run/current-system`. An `elif` compares their `kernel-modules` links and prints the driver hint, so it only appears when the kernel hint doesn't. This covers any out-of-tree module, not only NVIDIA, and doesn't need the script to know the driver's version. It doesn't depend on the fact either, so it applies to every machine.

Nightly upgrades already use `operation = "boot"` and need no change: the running module and its libraries stay in step until the reboot.

## Risks / Trade-offs

- [`"unstable"` stops building against the stable kernel] → The driver check fails the lock update, so machines don't receive the break. A machine that does hit a build failure keeps running and keeps its boot entry, but gets no updates until it's resolved.
- [A broken unstable driver holds back the lock update for all machines, including those on stable] → Accepted. It's a visible open PR with a failed check, and a human decides. If it becomes a nuisance, the unstable check can stop gating the update, or machines can move back to stable.
- [The path to unstable's `nvidia-x11/default.nix` changes] → The driver check fails on the lock update PR, and the path is one line in `nvidia.nix`.
- [Longer installs and updates on NVIDIA machines because `nvidia-x11` isn't cached, and on `"unstable"` the kernel module too] → Documented in the README. Stable remains the default.
- [NVIDIA's download URL goes away for an older driver, or the server is down during an update] → The update fails, and the machine keeps running its current generation.
- [`open = true` on a pre-Turing GPU installed by someone outside the current fleet] → The prompt states the requirement, and `--no-nvidia` or declining avoids it. The driver isn't validated against the GPU's generation.
- [`nixos-central upgrade` activates a new driver with the old module still loaded] → GPU programs may fail until reboot. The upgrade command says so (D7). Nightly upgrades aren't affected.
- [Scripts or compose files using `--gpus` or `runtime: nvidia`] → Only CDI device names are provided. Check them against the real machine, and the README documents the CDI form.
- [Fine-grained power management interacts badly with the CDI generator or Docker, leaving the GPU awake] → Part of the hardware verification (task 7.3). If it can't be fixed, turn fine-grained off centrally; the fact doesn't need to change.
- [PRIME, GDM and suspend can't be tested in VMs] → Hardware verification on this laptop before these are considered done.
- [No NVIDIA desktop is available for testing, so a display attached to the NVIDIA GPU is never exercised on real hardware] → Accepted. Fact detection and the resulting options are checked without hardware (task 7.4). The first real desktop is the first real test; a fix goes into `modules/base/nvidia.nix`, and the machine can boot an earlier generation meanwhile.

## Migration Plan

New installs get the fact from the installer. Existing NixOS machines keep building unchanged and can add the `nvidia` line to `/etc/nixos/flake.nix` by hand. To move this laptop:

1. Before merging, verify the branch on this laptop by installing from the image with `NIXOS_CENTRAL_FLAKE` set (task 7.2). This erases the disk, so back up first; the installer's normal confirmation applies.
2. Merge, then install the other machines from the image as usual.
3. Set `channel = "unstable"` in a machine flake only if 595 proves insufficient there.

Rollback on a machine: set `nvidia = null` or boot an earlier generation from the systemd-boot menu.

## Open Questions

- Whether NVIDIA power management needs changes for specific machines' suspend behavior. It's handled centrally if it comes up, without changing the fact.
