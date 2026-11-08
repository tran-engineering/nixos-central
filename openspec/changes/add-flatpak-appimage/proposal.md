# Proposal

## Why

Many desktop apps people want (Spotify, Discord, Zoom, vendor tools, apps
downloaded as an AppImage) are missing from nixpkgs, lag behind, or need Nix
knowledge to add to a profile. Users of graphical machines currently have no
way to install such an app themselves: KDE's Discover only shows firmware
updates, GNOME has no app store at all, and a downloaded AppImage does not
start on NixOS.

## What Changes

- Every graphical desktop (all desktops except `none`) gets Flatpak with
  Flathub configured system-wide, so apps can be installed from the command
  line (`flatpak install flathub …`) and, on KDE and GNOME, from the app store
  (Discover, GNOME Software).
- Installed Flatpak apps are updated automatically once a day, independently
  of the NixOS upgrade and without a reboot.
- Every graphical desktop can run AppImages directly (`./App.AppImage` or a
  double-click), without `appimage-run` in front.
- GNOME now gets GNOME Software (nixpkgs installs it together with Flatpak),
  which also lists firmware updates.
- Out of scope: declaring Flatpak apps in profiles (installed apps are local to
  the machine, not tracked by the repository), Flatpak in standalone homes on
  other distributions, an app store on `niri-noctalia`, and other managers
  (Distrobox, nix-ld, Snap, Homebrew).

## Capabilities

### New Capabilities
- `desktop-apps`: apps from outside nixpkgs on graphical machines: Flatpak
  with Flathub, its automatic updates, and running AppImages.

### Modified Capabilities
<!-- none: "Graphical desktops share common services" in host-configuration is
     left as is; the new behavior lives in its own capability. -->

## Impact

- New base modules under `modules/base/` (imported from
  `modules/base/default.nix`), active only when the desktop is not `none`.
- `modules/desktops/gnome.nix`: comment about GNOME Software becomes outdated.
- New VM checks in `nixos-central-internal/tests/default.nix`.
- README: new section on installing apps; desktops and firmware sections
  mention the app stores.
- Machines on `none` are unchanged. Existing machine flakes need no edits.
- Flatpak apps are outside Nix: they are not rolled back with a boot
  generation and do not appear in `nixos-central diff`.
