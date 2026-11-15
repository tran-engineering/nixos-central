# Design

## Context

- The home installer (`home-only.sh`, `detect_nvidia`) reads the loaded driver version from `/proc/driver/nvidia/version` and the hash from `nix store prefetch-file`. It writes them into the template line `nvidia = { version = "…"; sha256 = "…"; }; # host's NVIDIA driver …` of `~/.config/home-manager/flake.nix`. Homes without a driver get `nvidia = null;`.
- `mkHome` passes the pin to home-manager's `targets.genericLinux.gpu.nvidia`. That module builds `gpu.drivers` and `gpu.setupPackage`. On every activation, it compares `readlink /run/opengl-driver` with `gpu.drivers` and warns `sudo <setup>` when they differ. That warning already covers the daily upgrade's logging requirement.
- `nixos-central upgrade` for homes (`nixos-central-internal/home-upgrade/default.nix`) backs up `flake.lock`, runs `nix flake update`, builds with progress, then switches. It restores the lock if the home-manager profile did not move.
- The daily upgrade is home-manager's `home-manager-auto-upgrade` service. It runs `preSwitchCommands` (under `set -euo pipefail`, in the flake directory) and then `home-manager switch`. `standalone.nix` sets those commands to `nix flake update central [private]`.

## Goals / Non-Goals

**Goals:**
- One shared pin-sync script, used by both upgrade paths.
- Nothing in the sync can make an upgrade fail. Every problem becomes a warning and the old pin stays.
- Testable without a GPU or network, through test-only environment overrides, as `NIXOS_CENTRAL_NOTICE_*` already does.

**Non-Goals:**
- Changing `home-only.sh`'s detection. It keeps its own copy of the version parsing. The pattern is the same one home-manager validates, and the duplication is small.
- Handling driver updates made by the distribution between upgrades. Between the distribution update and the next upgrade, Nix GPU programs stay broken (see Risks).
- NixOS machines.

## Decisions

### Pure pin rewrite instead of `--impure`
Covered in the proposal. The pin stays a plain fact in the local flake, so manual `home-manager switch`, CI and the installer keep working unchanged.

### Read the pin from the line, not by evaluating
The sync script parses the `nvidia = …;` line with `sed`/`grep`. It does not `nix eval` the home configuration.
- Evaluating would fetch `central` and evaluate the whole home before every upgrade, and a broken `central` would break the check.
- The line has a fixed shape written by the template. The script accepts exactly one line matching `^\s*nvidia = null;` or `^\s*nvidia = { version = "<v>"; sha256 = "<h>"; };` (any trailing comment). Anything else gets the "update by hand" warning.
- The rewrite replaces only the two quoted values in that line, so indentation and the comment stay as they are.

### Where the host version comes from
`/proc/driver/nvidia/version`, parsed like the installer does (first `NNN.NN[.NN]` match). It exists only while the proprietary or open NVIDIA module is loaded, which is the "driver loaded" condition in the spec. The test override is `NIXOS_CENTRAL_NVIDIA_VERSION_FILE`.

### Download URL
`https://download.nvidia.com/XFree86/Linux-<arch>/<v>/NVIDIA-Linux-<arch>-<v>.run`, with `<arch>` from `uname -m` (`x86_64` or `aarch64`). This is the same URL as the installer and home-manager's `mkDriver`. The test override `NIXOS_CENTRAL_NVIDIA_BASE_URL` replaces `https://download.nvidia.com/XFree86`, so the VM test can point it at a `file://` tree. The hash comes from `nix store prefetch-file --json`. The download lands in the store, so the following build does not download the driver again.

### Shape of the script
A `writeShellApplication` package, `nixos-central-nvidia-pin <flake-dir>`, next to the home upgrade (`nixos-central-internal/home-upgrade/nvidia-pin.nix`). It always exits 0 and writes warnings to stderr. It is used by:
- the upgrade command, as a runtime input, run before `nix flake update`;
- the daily upgrade, as the first entry of `preSwitchCommands` in `standalone.nix`, by store path. A failure there would abort the whole upgrade under `set -e`, which is why the script must exit 0.

### Restoring `flake.nix`
The upgrade command copies `flake.nix` into its temporary directory next to the lock backup. When it restores the lock (profile unchanged), it also restores `flake.nix`, but only if the file differs from the backup, so its timestamp stays put in the normal case. The message stays "nothing was changed."

### GPU setup after the switch
After a successful switch, the command runs one `nix eval --raw` on `homeConfigurations."<user>".config.targets.genericLinux.gpu`, which prints `<drivers> <setup-exe>` when GPU integration is enabled and nothing otherwise. The flake and lock are unchanged since the build, so this only re-evaluates. Then:
- if `readlink /run/opengl-driver` equals `<drivers>`, it does nothing;
- if stdin and stdout are a terminal, it runs `sudo <setup-exe>`. If that fails or is cancelled, it prints the command and still exits 0;
- otherwise it prints `sudo <setup-exe>`.

The command checks `/run/opengl-driver` itself instead of parsing home-manager's activation warning. That keeps it independent of that warning's wording. Home-manager prints its own warning during the switch as well; the duplication is accepted.

Alternative considered: also give the daily upgrade a stronger notice through `nixos-central status` / the shell update notice. Not needed for the spec, because home-manager's activation warning already logs it. It is a possible follow-up.

## Risks / Trade-offs

- [The distribution updates the driver, and Nix GPU programs break until the next upgrade (up to a day, or until the user runs `nixos-central upgrade`).] → The README tells users to run `nixos-central upgrade` after a driver update. That is also the fastest fix.
- [A ~400 MB download during an upgrade, possibly on a metered connection.] → It only happens when the loaded version changed, and the following build reuses the same store path.
- [The loaded module differs from the installed userspace, for example after a distribution update but before a reboot. The pin then follows the old, still-loaded driver.] → That is correct for the running session. The next upgrade after the reboot moves the pin again.
- [A hand-edited `nvidia` line is not recognised.] → A warning tells the user what to edit, and the upgrade continues.
- [The sudo step cannot be covered by the offline VM test, because it needs a real home build.] → The pin sync and the `flake.nix` restore are tested. The setup step is verified by hand on an NVIDIA host (this machine: Arch, 620.70.06).

## Migration Plan

No migration. Existing home flakes written by the installer already have the expected line. Homes pick up the change through their next upgrade. The new upgrade command is only active after the switch that installs it, so the first driver resync happens on the upgrade after that.
