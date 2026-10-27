# Proposal

## Why

Personal profiles now live in private overlays, and overlays can't declare inputs. kt's overlay needs two things only central can provide: KDE Plasma settings through plasma-manager's home module, and logseq from nixos-unstable, which depends on an Electron release nixpkgs marks insecure.

## What Changes

- Add `plasma-manager` as a flake input (following central's nixpkgs and home-manager) and its home module to every profile on NixOS and standalone homes. Its options do nothing unless a profile sets `programs.plasma`.
- Permit `electron-39.8.10` in the shared package configuration, so `pkgs.unstable.logseq` can be installed. It applies to stable and unstable packages alike and only matters where something uses that Electron.

## Capabilities

### New Capabilities
<!-- None -->

### Modified Capabilities
- `user-profiles`: profiles (and overlays) can configure KDE Plasma; logseq from unstable is installable.

## Impact

- `flake.nix`/`flake.lock`: new input `plasma-manager`. The daily flake-update workflow updates it with the others.
- `modules/user.nix` (`home-manager.sharedModules`) and `lib.mkHome`: the plasma-manager home module.
- `nixos-central-internal/lib/nixpkgs.nix`: `permittedInsecurePackages`, to be revisited when nixos-unstable moves logseq to a supported Electron.
- `users/ci-modules` sets a Plasma option, so CI evaluates the module on NixOS, standalone x86_64 and aarch64.
