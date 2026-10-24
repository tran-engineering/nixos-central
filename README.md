# nixos-central

One central NixOS configuration for many machines. Anyone can install it from a
NixOS USB stick with a single command; afterwards every machine follows this
repository automatically.

## Install

1. Download the [NixOS installation image](https://nixos.org/download/#nixos-iso)
   (graphical or minimal) and write it to a USB stick. On Linux, this downloads
   the minimal image for 64-bit PCs and writes it in one go; replace `/dev/sdX`
   with the USB stick (find it with `lsblk`). Everything on the stick is erased.

   ```sh
   curl -L https://channels.nixos.org/nixos-26.05/latest-nixos-minimal-x86_64-linux.iso | sudo dd of=/dev/sdX bs=4M conv=fsync status=progress
   ```
2. Boot the computer from the USB stick **in UEFI mode**.
3. Connect to the network. Cable works out of the box; for Wi-Fi run `nmtui`
   (graphical image: use the network applet; minimal image: `nmtui` or `nmcli`).
4. Open a terminal and run:

   ```sh
   curl -sL https://tran-engineering.github.io/nixos-central | sh
   ```

   or, answering the questions up front:

   ```sh
   curl -sL https://tran-engineering.github.io/nixos-central | sh -s -- --hostname foo --user alice --desktop kde
   ```

Prefer to read the script before running it?

```sh
curl -sLo install.sh https://tran-engineering.github.io/nixos-central
less install.sh
sh install.sh
```

### Options

| Option | Default | Notes |
|---|---|---|
| `--hostname NAME` | asked, suggests `nixos-xxxx` | lowercase letters, digits, dashes |
| `--user NAME` | asked | lowercase, starts with a letter, max. 32 chars; system names (`root`, …) are reserved |
| `--desktop NAME` | asked, suggests `kde` | one of the [desktops](#desktops) |
| `--disk DEVICE` | first internal disk ≥ 40 GiB | still needs the typed confirmation |

Values passed as options are not asked for; invalid option values stop the
installer before anything is changed.

### What the installer does

1. Checks it runs on the NixOS live image, booted in UEFI mode, with access to GitHub.
2. Asks for hostname, username and desktop (unless given as options).
3. Picks the disk: the first whole disk of at least 40 GiB that is not removable,
   not connected via USB, and not the USB stick it booted from. It shows device,
   size and model and continues only if you type `yes`.
4. Asks for the **disk passphrase** (needed at every boot) and offers to use it as
   your login password too; otherwise asks for a separate login password.
   Neither is stored in plain text; only a password hash ends up on the disk
   (`/etc/secrets/<user>.hash`), never in the Nix store.
5. Erases the disk: 1 GiB EFI partition, the rest LUKS-encrypted btrfs
   (subvolumes `@`, `@home`, `@nix`).
6. Writes the machine's configuration to `/etc/nixos` and installs NixOS.
7. Shows a summary and asks to reboot.

On failure it names the failed step and the log file
(`/tmp/nixos-central-install.log` on the live system) and does not reboot.

## How a machine is configured

Each machine has a small flake in `/etc/nixos` with only its own facts; the rest
comes from this repository (the `central` input):

```nix
# /etc/nixos/flake.nix (written by the installer)
{
  inputs.central.url = "github:tran-engineering/nixos-central";
  outputs = { central, ... }: {
    nixosConfigurations."foo" = central.lib.mkHost {
      hostname = "foo";
      user = "alice";
      desktop = "kde";
      disk = "/dev/disk/by-id/nvme-...";
      stateVersion = "26.05";  # release the machine was installed with; never change
      modules = [ ./hardware-configuration.nix ];
    };
  };
}
```

`central.lib.mkHost` arguments:

| Argument | Meaning |
|---|---|
| `hostname` | machine name |
| `user` | primary user (admin via `sudo`) |
| `desktop` | one of the [desktops](#desktops) |
| `disk` | disk the system was installed on |
| `stateVersion` | NixOS release at install time |
| `modules` | extra NixOS modules; the installer adds `hardware-configuration.nix` |

To change the desktop later, edit `desktop` in `/etc/nixos/flake.nix` and run
`sudo nixos-rebuild switch --flake /etc/nixos`.

### Desktops

| Name | Desktop |
|---|---|
| `gnome` | GNOME (Wayland, GDM) |
| `kde` | KDE Plasma 6 (Wayland, SDDM) |
| `niri-noctalia` | [niri](https://github.com/YaLTeR/niri) tiling compositor with the [Noctalia](https://github.com/noctalia-dev/noctalia-shell) shell (Wayland, SDDM) |
| `none` | no graphical desktop, console login |

On `niri-noctalia`, the main keys are:

| Key | Action |
|---|---|
| `Mod+Shift+/` | show all keybindings |
| `Mod+D` | application launcher |
| `Mod+T` | terminal (Alacritty) |
| `Mod+Q` | close window |
| `Super+Alt+L` | lock screen |
| `Mod+X` | session menu (log out, reboot, shut down) |

`Mod` is the Super ("Windows") key. The config is
`modules/desktops/niri-noctalia/config.kdl`, installed as `/etc/niri/config.kdl`.
To use your own, add it to your profile; Noctalia still starts:

```nix
xdg.configFile."niri/config.kdl".source = ./niri.kdl;
```

A new desktop is a new file `modules/desktops/<name>.nix`, enabled with
`lib.mkIf (config.nixos-central.desktop == "<name>")`. Sound, Bluetooth and
printing for every graphical desktop come from `modules/base/graphical.nix`.

## Users and profiles

The primary user's environment is a [home-manager](https://github.com/nix-community/home-manager)
profile from this repository:

- `users/<name>/` if it exists,
- otherwise the shared default `users/_default/`.

This is decided every time the system is built, so a profile added later is
picked up by the machine's next update. A personal profile **replaces** the
default; to build on it, import it:

```nix
# users/alice/default.nix
{ pkgs, lib, ... }:
{
  imports = [ ../_default ];
  home.packages = [ pkgs.gimp ];
  home.sessionVariables.EDITOR = lib.mkForce "nano";
}
```

Newer versions of single packages come from `nixos-unstable` as
`pkgs.unstable.<name>` (unfree allowed, as for the stable packages). Everything
not taken from `pkgs.unstable` stays on the system's NixOS release:

```nix
home.packages = [ pkgs.unstable.helix ];
```

Permanent changes go through a pull request to this repository. To try a
package without changing anything:

```sh
nix-shell -p ripgrep          # or: nix shell nixpkgs#ripgrep
nix run nixpkgs#gimp
NIXPKGS_ALLOW_UNFREE=1 nix shell --impure nixpkgs#discord   # unfree packages
```

These use the same nixpkgs version as the installed system.

## Updates

- Every day (or soon after boot, if the computer was off) each machine fetches
  the latest `main` of this repository, builds it and makes it the **default for
  the next boot**. The running system is not changed and the computer is never
  rebooted automatically.
- Desktop users get a notification *"Update ready – reboot when convenient"*.
- If an update is broken, choose the previous entry in the boot menu, or go
  back to the previous generation right away with
  `sudo nixos-rebuild switch --rollback`.
- Stage the latest update for the next boot right away (like the daily run):
  `sudo systemctl start nixos-upgrade`.
- Install the latest update **and use it now**: `nixos-central-upgrade`. It
  also becomes the default for the next boot. Switching may restart services
  (and the desktop), so save your work first. A new kernel is used only after
  the next reboot; the command says so when that applies.

### Trying a branch

```sh
nixos-central-try my-branch
```

Activates this machine's configuration built from `my-branch` of this repository
**until the next reboot**. It creates no boot entry and does not change
`/etc/nixos`. Typical flow: push a branch with your profile changes, try it,
open a pull request when happy.

## Development

```sh
nix flake check                       # evaluates and builds sample hosts, runs VM tests
nix build .#checks.x86_64-linux.shells
nix run --impure -f nixos-central-internal/tests/e2e   # full installer test in QEMU (needs KVM + internet)
shellcheck nixos-central-internal/installer/install.sh
```

Sample hosts used in CI: `ci-gnome`, `ci-kde`, `ci-niri-noctalia`, `ci-none`, `ci-default-profile`
(`nixosConfigurations`, not meant to be installed).
