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

## Install on another Linux distribution

Your [profile](#users-and-profiles) also works without NixOS, e.g. on Ubuntu,
Fedora or Arch (x86_64 or aarch64). Run as yourself, not as root:

```sh
curl -sL https://tran-engineering.github.io/nixos-central/home-only.sh | sh
```

It changes only your home directory, except for two steps it asks about first:
installing [Nix](https://nixos.org/download) if it is missing, and a one-time
GPU driver setup (both need `sudo`). It sets up your current login name, so a
different name than on your NixOS machines is fine: pick the profile you want.

| Option | Default | Notes |
|---|---|---|
| `--profile NAME` | asked; suggests your login name's profile, else `_default` | one of the profiles in `users/` |
| `--install-nix` | asked | install Nix if missing |
| `--replace-existing` | asked | move an existing `~/.config/home-manager` aside (`.backup-<date>`) |
| `--gpu-setup` / `--no-gpu-setup` | asked, suggests yes | |

Files in your home that the profile takes over (e.g. `~/.bashrc`) are kept as
`<file>.backup`. Your login shell is not changed; if the profile
[selects](#login-shell) fish or zsh, the installer prints how to switch.

The home's facts live in `~/.config/home-manager/flake.nix` (login name, home
directory, profile, NVIDIA driver); everything else comes from this repository.
It updates itself daily (`systemctl --user list-timers home-manager-auto-upgrade.timer`).
New terminals tell you when it has not managed to update for a while
([update notice](#updates)).
Run by hand:

```sh
nixos-central-upgrade             # update now (central, and your private overlay if any)
nixos-central-upgrade --private   # update only the private overlay
nixos-central-diff                # packages the last update changed
nixos-central-update-notice       # when the last update succeeded, how old things are
home-manager generations          # then run <generation path>/activate to roll back
```

Old generations are cleaned up weekly, as on NixOS ([Updates](#updates)):
`home-manager generations` lists those of the last 30 days and the one in use 30
days ago.

**GPU drivers.** Graphical programs from Nix need the drivers set up once per
machine: `sudo <path>/bin/non-nixos-gpu-setup` (the installer runs it or prints
the exact command; home-manager reminds you when it is needed). With the
proprietary NVIDIA driver, the installer records its version; after the
distribution updates the driver, run the installer again with
`--replace-existing` so the recorded version matches.

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

`pkgs.unstable.logseq` is allowed although it is built on an end-of-life
Electron: the shared package configuration permits exactly that Electron
release (`nixos-central-internal/lib/nixpkgs.nix`), and nothing else marked
insecure.

KDE Plasma settings (theme, shortcuts, touchpads, any KDE config file) can be
set declaratively with [plasma-manager](https://github.com/nix-community/plasma-manager),
which every profile and overlay has:

```nix
programs.plasma = {
  enable = true;
  workspace.colorScheme = "BreezeDark";
  shortcuts.kwin."Window Close" = "Meta+Shift+Q";
};
```

This repository holds only what is useful to anyone. Your own setup (which
modules you use, your name and email, fonts, themes, work files) belongs in
your [private overlay](#private-overlay), not in a profile here.

Permanent changes to shared configuration go through a pull request to this
repository. To try a package without changing anything:

```sh
nix-shell -p ripgrep          # or: nix shell nixpkgs#ripgrep
nix run nixpkgs#gimp
NIXPKGS_ALLOW_UNFREE=1 nix shell --impure nixpkgs#discord   # unfree packages
```

These use the same nixpkgs version as the installed system.

### Shared modules

Sets of tools a profile can opt into, in `modules/home/`. They work on NixOS
and on other distributions alike:

| Module | Provides |
|---|---|
| `general-tools.nix` | everyday CLI utilities: `bat`, `eza`, `dust`, `ncdu`, `7z`, `yt-dlp`, `ffmpeg`, `imagemagick`, `exiftool`, `nslookup`, … |
| `dev-cli` | development tooling: `rg`, `just`, `jq`, `gh`, `lazygit`, `rustup`, `uv`, `claude`, `opencode`, Kubernetes/Terraform/AWS CLIs, Nix tooling; cargo and pnpm binaries on the `PATH`, Node.js via mise |
| `git.nix` | git with Git LFS; rebase on pull, push sets the upstream |
| `jj.nix` | jj and `jjui`; bookmarks track `origin`, commits described `wip:`/`private:` are not pushed |
| `dev-desktop.nix` | the Zed editor (`zed`) with its Claude agent |
| `idea.nix` | IntelliJ IDEA |
| `godot.nix` | Godot |
| `drawio.nix` | draw.io |
| `fish` | fish with the tide prompt, `fzf` search, `z`, `cd-gitroot` |
| `zsh.nix` | zsh with completion, autosuggestions, syntax highlighting, shared history |
| `foot.nix` | the foot terminal |
| `ghostty.nix` | the Ghostty terminal |

The fish prompt and the terminals come with an icon font, so the prompt's
icons render whatever main font you choose. To use your own tide prompt, run
`tide configure`, save the result as described in
`modules/home/fish/tide.fish`, and point
`xdg.configFile."fish/conf.d/tide.fish".source` at it.

Pick modules by name with `centralModules`, which every profile and private
overlay receives:

```nix
# homeModules.default of your private overlay
{ centralModules, ... }:
{
  imports = with centralModules; [ dev-cli git godot ];
}
```

Profiles inside this repository can do the same, or import by path
(`../../modules/home/dev-cli`). The module names are an interface for overlays:
renaming or removing one is a breaking change.

The modules set no names or emails; put those in your overlay. Their workflow
defaults (git, jj, and Node.js 24 in `dev-cli`) are overridden by setting the
same option:

```nix
programs.git.settings.pull.rebase = false;
programs.mise.globalConfig.tools.node = [ "22" ];
```

### Login shell

The login shell is bash unless the profile selects another one:

```nix
nixos-central.shell = "fish";   # "bash" (default), "fish" or "zsh"
```

NixOS machines switch to it with their next update (log in again). On another
Linux distribution, changing the login shell needs root, so the home installer
prints the `chsh` command instead. Selecting a shell installs it; import the
`fish` or `zsh` module as well for the configuration above.

Profiles named `ci-*` (e.g. `users/ci-user`) exist only for tests and are not
offered by the home installer.

### Private overlay

Your own setup lives in a private repository you control: which shared
modules you use, your login shell, name and email, fonts and themes, and files
that must not be public (work SSH configuration, internal scripts). It is added
to a machine after installation and applied on top of the default profile.

The overlay is a flake **without inputs** that only exports modules, one per
profile; packages and options come from this repository. Like `users/` here,
it can hold several people's profiles:

```nix
# flake.nix in your private repository
{
  outputs = _: {
    homeModules.alice = { centralModules, pkgs, ... }: {
      imports = with centralModules; [ dev-cli git fish ghostty ];
      nixos-central.shell = "fish";
      programs.git.settings.user = { name = "Alice"; email = "alice@example.com"; };
      home.file.".ssh/config".source = ./alice/ssh/config;
    };
    homeModules.bob = { centralModules, ... }: {
      imports = with centralModules; [ general-tools ];
    };
    # Optional fallback for users without a profile of their own:
    # homeModules.default = { ... }: { };
    # Optional, NixOS machines only:
    # nixosModules.default = { ... }: { };
  };
}
```

The profile is chosen by the same name as here: the primary user's name on
NixOS, the recorded `profile` on other distributions. Without a matching
profile, `homeModules.default` is used; if that doesn't exist either, the build
fails and lists the overlay's profiles.

Set it up after the first boot (NixOS) or after `home-only.sh` (other
distributions):

1. Copy your SSH key to `~/.ssh/id_ed25519`. It must have no passphrase,
   because daily updates fetch the overlay without you. Its public key must be
   added to your GitHub account.
2. Run:

   ```sh
   nixos-central-private setup git+ssh://git@github.com/alice/private
   ```

   It checks that the key can read the repository, adds the overlay to
   `/etc/nixos/flake.nix` (or `~/.config/home-manager/flake.nix`) and
   activates it. If anything fails, the flake is left as it was.

   On another distribution, add `--profile NAME` to use a profile that exists
   only in your overlay (the home installer only offers profiles from this
   repository, so install with `_default` first):

   ```sh
   nixos-central-private setup git+ssh://git@github.com/alice/private --profile alice
   ```

From then on, daily updates and `nixos-central-upgrade` update the overlay
together with this repository. On NixOS they run as root, which uses your
`~/.ssh/id_ed25519` for GitHub only. After pushing a change to the overlay,
`nixos-central-upgrade --private` uses it right away without updating this
repository.

If the overlay can't be fetched (key removed from GitHub, repository renamed),
updates **stop** instead of continuing without it: the machine keeps running
its current configuration, and `systemctl status nixos-upgrade` shows the
error. Fix access, or take the overlay out with `nixos-central-private remove`.

Losing a machine means its key can read the repository: remove that key from
your GitHub account.

## Updates

- Every day (or soon after boot, if the computer was off) each machine fetches
  the latest `main` of this repository, builds it and makes it the **default for
  the next boot**. The running system is not changed and the computer is never
  rebooted automatically.
- Desktop users get a notification *"Update ready – reboot when convenient"*.
- See which packages an update changes (as `nh` shows them): `nixos-central-diff`.
  While an update waits for a reboot, it compares the running system with it
  (*"Pending on next reboot"*); otherwise it shows what the last update changed
  (*"Changes from generation 40 to 41"*). No `sudo` needed. The notification
  mentions the command.
- If an update is broken, choose the previous entry in the boot menu, or go
  back to the previous generation right away with
  `sudo nixos-rebuild switch --rollback`.
- Old generations are cleaned up weekly: those of the last 30 days stay, and so
  does the one that was in use 30 days ago, so there is always a previous
  generation to go back to. The generation the machine is running or booted into
  is never removed, even if newer updates are waiting for a reboot. Older ones
  disappear from the boot menu. Your own `nix profile` installs are cleaned up
  the same way. To keep more, or to turn it off, in a module of your machine
  (`modules` in `/etc/nixos/flake.nix`) or in your profile:

  ```nix
  nixos-central.gc.keepDays = 90;           # machine; nixos-central.gc.enable = false; turns it off
  nix.gc.options = "--delete-older-than 90d"; # profile; nix.gc.automatic = false; turns it off
  ```
- Stage the latest update for the next boot right away (like the daily run):
  `sudo systemctl start nixos-upgrade`.
- Install the latest update **and use it now**: `nixos-central-upgrade`. It
  also becomes the default for the next boot. Switching may restart services
  (and the desktop), so save your work first. A new kernel is used only after
  the next reboot; the command says so when that applies.
  `nixos-central-upgrade --private` updates only your
  [private overlay](#private-overlay) and leaves this repository at the
  installed revision. Standalone homes have the same command (no `sudo`).
- When no update has succeeded for more than 7 days, every new terminal says so,
  with what to do (reboot into a staged update, run `nixos-central-upgrade`, or
  check the daily update). It also shows how old the running system and the
  pinned revision of this repository are. A successful daily update counts even
  if nothing changed, so a quiet repository causes no notice. Homes on
  [other distributions](#install-on-another-linux-distribution) get the same
  notice. `nixos-central-update-notice` shows the same at any time. Change the
  number of days in your profile, `0` turns the terminal notice off:

  ```nix
  nixos-central.updateNotice.days = 14;
  ```

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
nix build .#desktopTests.reboot-notify-kde   # full KDE/GNOME desktop tests, not in flake check (10–15 min each)
nix run --impure -f nixos-central-internal/tests/e2e   # full installer test in QEMU (needs KVM + internet)
shellcheck nixos-central-internal/installer/install.sh
shellcheck nixos-central-internal/installer/home-only.sh
```

Sample hosts used in CI: `ci-gnome`, `ci-kde`, `ci-niri-noctalia`, `ci-none`, `ci-default-profile`
(`nixosConfigurations`, not meant to be installed). Sample standalone homes:
`ci-home-default`, `ci-home-renamed`, `ci-home-aarch64`, `ci-home-modules-aarch64`
(`homeConfigurations`). Every selectable profile is also evaluated standalone
(`home-profile-<name>` checks). The test profile `users/ci-modules` uses every
shared module and is evaluated on NixOS and standalone (`host-eval-ci-modules`,
`home-eval-ci-modules`). `central-modules` guards the module names overlays
rely on; `overlay-eval` and `overlay-rejects-inputs` test private overlays with
`nixos-central-internal/tests/overlay`. These checks don't build packages;
those come from the NixOS binary cache.
The update notification is tested headless with a stub notification server
(`reboot-notify`); `desktopTests.reboot-notify-kde` and `-gnome` check it in a
real desktop session and are run by hand, as CI runs only `nix flake check`.
