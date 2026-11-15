# Proposal

## Why

A standalone home on a host with an NVIDIA GPU records the host's driver version and hash in `~/.config/home-manager/flake.nix`, and the Nix copy of the driver must match the loaded kernel module exactly. When the host distribution updates its driver (for example Arch from 615.78.08 to 620.70.06), the pin goes stale. Graphical Nix programs such as Zed then fail to find a usable GPU, and nothing in the home tells the user why or fixes it. Today the only fix is to fetch the new hash by hand, edit the flake, switch, and rerun the GPU setup with sudo.

## What Changes

- Before building, `nixos-central upgrade` and the daily automatic home upgrade compare the host's loaded NVIDIA driver version with the version pinned in the local flake. If the home pins a driver and the versions differ, they download the new driver, compute its hash and rewrite the pin in `~/.config/home-manager/flake.nix`. The build stays pure; no `--impure` is needed.
- If the new driver cannot be fetched, a warning is printed and the upgrade continues with the old pin.
- Homes without a pinned driver (`nvidia = null`) and hosts without a loaded NVIDIA driver are left alone. A pin is never added or removed automatically.
- If `nixos-central upgrade` fails before a new generation is installed, it restores `flake.nix` as well as `flake.lock`.
- After a successful switch, if the system-wide GPU links (`/run/opengl-driver`) do not point to the new home's drivers, `nixos-central upgrade` runs the GPU setup with `sudo` when it runs in a terminal. The sudo password prompt is the user's consent. Otherwise it prints the command to run. The daily upgrade never uses sudo. It only logs that the setup is needed.
- **Rejected alternative:** reading the driver version from `/sys` in `mkHome` under `--impure`. Every switch path (manual `home-manager switch`, daily timer, installer, CI) would need `--impure`, and evaluation would download the ~400 MB driver.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `home-configuration`:
  - "GPU integration with the host": the root setup is no longer strictly one-time. It is needed again after the drivers change, and `nixos-central upgrade` may run it with consent.
  - "Daily automatic home upgrade" and "Upgrading the home immediately on demand": both also keep the NVIDIA pin in the local flake in step with the host driver, and their failure guarantees also cover `flake.nix`.

## Impact

- **Code:** `nixos-central-internal/home-upgrade/default.nix` (pin sync, flake.nix restore, GPU setup after switch); a new shared pin-sync script next to it; `modules/home/standalone.nix` (daily upgrade's `preSwitchCommands`); `nixos-central-internal/tests/default.nix`; `README.md`.
- **Local home flakes:** the upgrade now edits one line of `~/.config/home-manager/flake.nix`, the `nvidia = …;` line the installer wrote. Flakes without that line in the template's shape are left unchanged, with a warning.
- **Network:** a driver change triggers one download of the driver (~400 MB) from `download.nvidia.com` during the upgrade.
- **Root access:** `nixos-central upgrade` may prompt for the sudo password after a driver change. Without a terminal, nothing is run as root.
- **NixOS machines:** unaffected; their driver comes from nixpkgs (`nvidia-graphics`).
