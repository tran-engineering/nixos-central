# Proposal

## Why

Machines can choose only between `kde` and `none`. Some users want GNOME, and some want a tiling setup: the niri scrollable-tiling compositor with the Noctalia shell (bar, launcher, notifications, lock screen). Separately, users want single newer packages than nixos-26.05 offers, so the repository gets a nixpkgs-unstable input that profiles can use.

## What Changes

- New desktop `gnome`: GNOME on Wayland with the GDM login screen.
- New desktop `niri-noctalia`: niri with the Noctalia shell started automatically in every niri session, the SDDM login screen, and a central default niri configuration (keybindings that launch Noctalia's launcher, a terminal, lock screen and so on). Users can replace it with their own niri configuration from their profile.
- niri and Noctalia come from nixos-26.05. Unstable was planned, but its Noctalia fails to build against Qt 6.12, and its niri is the same version as stable. Moving them to unstable later is a one-line change.
- New flake input `nixpkgs-unstable`; the system itself stays on nixos-26.05.
- Unstable packages are available as `pkgs.unstable.<name>` in NixOS modules and in user profiles.
- Shared pieces of graphical desktops (audio, Bluetooth, printing) move out of the KDE module so every graphical desktop gets them.
- CI builds a sample host for each new desktop, and the VM tests check that each graphical desktop starts and shows the reboot-pending notification.
- README desktop table and profile docs are updated. The installer lists the new desktops automatically (it reads them from the repository).

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `host-configuration`: the offered desktops now include `gnome` and `niri-noctalia`, with scenarios for each.
- `user-profiles`: adds a requirement that profiles can use packages from nixpkgs-unstable.

## Impact

- `flake.nix` / `flake.lock`: new input `nixpkgs-unstable`. Every machine locks a second nixpkgs source; only profiles that use `pkgs.unstable` download unstable packages. The weekly `flake.lock` update PR now also bumps unstable.
- New `modules/desktops/gnome.nix`, `modules/desktops/niri-noctalia.nix` (plus its niri config file), a shared graphical-desktop module in `modules/base`, an overlay for `pkgs.unstable`.
- `modules/desktops/kde.nix` loses the parts that move to the shared module (no behavior change for `kde` machines).
- `flake.nix` sample hosts `ci-gnome`, `ci-niri-noctalia`; `nixos-central-internal/tests/default.nix` desktop tests.
- `README.md`.
- No change to `lib.mkHost`'s arguments; existing machine flakes keep working.
