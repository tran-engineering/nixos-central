# Proposal

## Why

A user's profile in `users/<name>` can only reach a machine today as part of a full NixOS install. On machines that run another Linux distribution (a work laptop, a shared desktop), users get nothing from the central repository, and k-nixos solves this with a separate flake and lock file that drift from the NixOS path. The profiles are already plain home-manager modules, so they can be delivered standalone from the same central repository.

## What Changes

- New central entry point for standalone homes: builds a home-manager configuration from login name, home directory, state version, platform, chosen profile and optional NVIDIA driver facts. Shares the package set (unfree, `pkgs.unstable`) and profile resolution with the NixOS host builder.
- New per-user local flake in `~/.config/home-manager`, holding only machine facts, analogous to `/etc/nixos`.
- Login name and profile are decoupled for standalone homes: the login name is taken from the running user, the profile is chosen from the profiles in the central repository (personal profile of the same name, otherwise `_default`, or any explicitly selected one).
- Standalone homes integrate with the host's GPU drivers (opt-in one-time root setup) and update themselves daily from the central repository.
- New installer script `home-only.sh`, published next to the NixOS installer, that runs as the normal user on any Linux distribution, installs Nix if missing, writes the local flake and activates the profile.
- The NixOS installer, when not started from a live image, points the user to the `home-only.sh` one-liner instead of only failing.
- CI builds standalone homes for the test profiles and runs `home-only.sh` end to end on a non-NixOS runner.

## Capabilities

### New Capabilities
- `home-configuration`: How a standalone (non-NixOS) user environment is composed from the central repository plus a thin per-user local flake; platform support, GPU integration and automatic updates of such homes.
- `home-installer`: The `home-only.sh` script: publication, preflight, Nix bootstrap, profile selection, first activation.

### Modified Capabilities
- `user-profiles`: Profiles must work both as part of a NixOS machine and standalone; a standalone home may use a profile whose name differs from the login name.
- `installer`: When not run from a NixOS live image, the abort message points to the standalone home installer.

## Impact

- `nixos-central-internal/lib/default.nix`: new `mkHome`, list of selectable profile names; shared package-set and profile-resolution code used by `modules/user.nix`.
- `modules/user.nix`: reuses the shared profile resolution; NixOS behaviour unchanged.
- New home-manager module(s) for standalone homes (GPU, auto-upgrade).
- `flake.nix`: `templates.home`, `packages.<system>.home-manager`, sample `homeConfigurations` built in checks.
- New `nixos-central-internal/installer/home-only.sh` and `nixos-central-internal/templates/home/flake.nix`.
- `nixos-central-internal/installer/install.sh`: preflight abort message only.
- `.github/workflows/pages.yml` (publish `/home-only.sh`), `.github/workflows/ci.yml` (shellcheck, end-to-end job on `ubuntu-latest`).
- `README.md`: new section on installing on other Linux distributions.
- No change to existing machine flakes or the `mkHost` interface.
