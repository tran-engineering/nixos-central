# nixos-central

One central NixOS configuration for many machines. Anyone can install it from
its USB image by answering a few questions; afterwards every machine follows
this repository automatically.

## Install

1. Download the nixos-central installation image (64-bit PCs, about 1.5 GB) and
   write it to a USB stick. On Linux, this downloads and writes it in one go;
   replace `/dev/sdX` with the USB stick (find it with `lsblk`). Everything on
   the stick is erased.

   ```sh
   curl -L https://github.com/tran-engineering/nixos-central/releases/latest/download/nixos-central-x86_64.iso | sudo dd of=/dev/sdX bs=4M conv=fsync status=progress
   ```

   To check the download first, fetch the image and its checksum and compare:

   ```sh
   curl -LO https://github.com/tran-engineering/nixos-central/releases/latest/download/nixos-central-x86_64.iso
   curl -LO https://github.com/tran-engineering/nixos-central/releases/latest/download/nixos-central-x86_64.iso.sha256
   sha256sum -c nixos-central-x86_64.iso.sha256
   ```

   On Windows or macOS, write the image with a tool such as
   [balenaEtcher](https://etcher.balena.io/).
2. Boot the computer from the USB stick **in UEFI mode**.
3. Answer the prompt on the screen. With a network cable, it asks
   *Install nixos-central on this computer?* right away. Without a network, it
   first offers to set one up: choose *Activate a connection* in `nmtui`, pick
   your Wi-Fi and enter its password.

The image always runs the **current** installer and configuration from this
repository, however old the image is. If you decline the prompt, you get a
shell; run `nixos-central-start` to get the prompt back.

To install a specific branch or revision, start it from the image's shell:

```sh
NIXOS_CENTRAL_FLAKE=git+https://github.com/tran-engineering/nixos-central?ref=my-branch nixos-central-start
```

### Already have a NixOS USB stick?

The installer also runs from the stock
[NixOS installation image](https://nixos.org/download/#nixos-iso). Take its
**graphical** image if the machine will be on a Wi-Fi that asks you to sign in
through a web page (hotel, university or guest networks): it has a browser for
that page, the minimal images have none. Boot it in UEFI mode, connect to the
network (cable, the network applet, or `nmtui`; with a sign-in page, sign in
with Firefox first), open a terminal and run:

```sh
curl -sL https://tran-engineering.github.io/nixos-central | sh
```

or, answering the questions up front:

```sh
curl -sL https://tran-engineering.github.io/nixos-central | sh -s -- --hostname foo --user alice --desktop kde
```

With your [private overlay](#private-overlay) and one of its profiles
(keep your phone at hand to add the new SSH key on GitHub):

```sh
curl -sL https://tran-engineering.github.io/nixos-central | sh -s -- --private git+ssh://git@github.com/alice/private --profile developer
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
| `--keyboard-layout NAME` | asked, suggests `us` | `us`, `de`, `sg` (Swiss German), `sf` (Swiss French) |
| `--private URL` | asked, suggests no overlay | flake URL of your [private overlay](#private-overlay); the question suggests the shared overlay |
| `--profile NAME` | asked, suggests your username if the overlay has it, else `default` | a profile of the overlay; only together with `--private` |
| `--nvidia` | asked if an NVIDIA GPU is found, suggests yes | installs the [NVIDIA driver](#nvidia-graphics) without asking; stops if no NVIDIA GPU is found |
| `--no-nvidia` | | no NVIDIA driver, and no question |

Values passed as options are not asked for; invalid option values stop the
installer before anything is changed.

### What the installer does

1. Checks it runs on the NixOS live image, booted in UEFI mode, with access to GitHub.
2. Asks for the keyboard layout first and switches this console to it, so the
   following answers — including the disk passphrase — are typed with it. Then
   asks for hostname, username and desktop (unless given as options). If it finds
   an NVIDIA GPU, it shows it and offers the [driver](#nvidia-graphics) (default:
   yes); if you accept, it also checks that `download.nvidia.com` can be reached.
3. Picks the disk: the first whole disk of at least 40 GiB that is not removable,
   not connected via USB, and not the USB stick it booted from. It shows device,
   size and model and continues only if you type `yes`.
4. Asks for the **disk passphrase** (needed at every boot) and offers to use it as
   your login password too; otherwise asks for a separate login password.
   Neither is stored in plain text; only a password hash ends up on the disk
   (`/etc/secrets/<user>.hash`), never in the Nix store.
5. Offers to set up a [private overlay](#private-overlay) (default: no). If you
   accept (or pass `--private`), it
   - generates an SSH key for you, **without passphrase**, because daily updates
     fetch the overlay with it unattended,
   - shows the public key as text and as a QR code: scan it with your phone and
     paste it on GitHub (Settings → SSH and GPG keys → New SSH key), then press Enter,
   - checks that the key can read the overlay; if not, you can retry or continue
     without the overlay (the key is installed anyway, for a later
     `nixos-central private setup`),
   - asks for one of the overlay's profiles, e.g. a generic `developer` profile
     for any username.
6. Erases the disk: 1 GiB EFI partition, the rest LUKS-encrypted ext4.
7. Writes the machine's configuration to `/etc/nixos` (with the overlay and
   profile, exactly as `nixos-central private setup` would) and installs NixOS.
   The key goes to `~/.ssh/id_ed25519` of your user.
8. Shows a summary and asks to reboot.

On failure it names the failed step and the log file
(`/tmp/nixos-central-install.log` on the live system) and does not reboot.

## Install on another Linux distribution

Your [environment](#users-and-profiles) also works without NixOS, e.g. on
Ubuntu, Fedora or Arch (x86_64 or aarch64). Run as yourself, not as root:

```sh
curl -sL https://tran-engineering.github.io/nixos-central/home-only.sh | sh
```

It changes only your home directory, except for two steps it asks about first:
installing [Nix](https://nixos.org/download) if it is missing, and a one-time
GPU driver setup (both need `sudo`). It sets up the base configuration for
your current login name. Your own profile comes from your
[private overlay](#private-overlay), added afterwards with
`nixos-central private setup [<flake-url>] --profile NAME`; a different login
name than on your NixOS machines is fine.

| Option | Default | Notes |
|---|---|---|
| `--install-nix` | asked | install Nix if missing |
| `--replace-existing` | asked | move an existing `~/.config/home-manager` aside (`.backup-<date>`) |
| `--gpu-setup` / `--no-gpu-setup` | asked, suggests yes | |

`--profile` is no longer accepted (profiles came from this repository before);
the installer stops and names the `nixos-central private setup` command instead.

Files in your home that the configuration takes over (e.g. `~/.bashrc`) are
kept as `<file>.backup`. Your login shell is not changed; if your profile
[selects](#login-shell) fish or zsh, the installer or `nixos-central private setup`
prints how to switch.

The home's facts live in `~/.config/home-manager/flake.nix` (login name, home
directory, NVIDIA driver, and the private overlay and its profile once added);
everything else comes from this repository. Homes installed earlier record
`profile = "_default";` there; that line is harmless and is replaced when you
add an overlay with `--profile`.
It updates itself daily (`systemctl --user list-timers home-manager-auto-upgrade.timer`).
New terminals tell you when it has not managed to update for a while
([update notice](#updates)).
Run by hand:

```sh
nixos-central upgrade             # update now (central, and your private overlay if any)
nixos-central upgrade --private   # update only the private overlay
nixos-central diff                # packages the last update changed
nixos-central status              # when the last update succeeded, how old things are
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
  inputs.central.url = "git+https://github.com/tran-engineering/nixos-central";
  outputs = { central, ... }: {
    nixosConfigurations."foo" = central.lib.mkHost {
      hostname = "foo";
      user = "alice";
      desktop = "kde";
      disk = "/dev/disk/by-id/nvme-...";
      keyboardLayout = "sg";
      stateVersion = "26.05";  # release the machine was installed with; never change
      nvidia = null;           # the machine's NVIDIA GPU, if any
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
| `keyboardLayout` | keyboard layout: `us`, `de`, `sg` (Swiss German) or `sf` (Swiss French); console and graphical session |
| `stateVersion` | NixOS release at install time |
| `nvidia` | optional: the machine's NVIDIA GPU (see [NVIDIA graphics](#nvidia-graphics)); default `null`, no driver |
| `profile` | optional: profile of the [private overlay](#private-overlay) to use instead of `user`'s name (see [Users and profiles](#users-and-profiles)); the account keeps the name `user`. Without an overlay it has no effect (the build warns) |
| `private` | optional: the [private overlay](#private-overlay) flake |
| `modules` | extra NixOS modules; the installer adds `hardware-configuration.nix` |

To change the desktop or keyboard layout later, edit `desktop` or
`keyboardLayout` in `/etc/nixos/flake.nix` and run
`sudo nixos-rebuild switch --flake /etc/nixos`.

### Desktops

| Name | Desktop |
|---|---|
| `gnome` | GNOME (Wayland), with a dock on the left ([Dash to Dock](https://extensions.gnome.org/extension/307/dash-to-dock/); move or turn it off in *Extensions*) |
| `kde` | KDE Plasma 6 (Wayland) |
| `niri-noctalia` | [niri](https://github.com/YaLTeR/niri) tiling compositor with the [Noctalia](https://github.com/noctalia-dev/noctalia-shell) shell (Wayland) |
| `none` | no graphical desktop, console login |

Every desktop logs in through GDM, which can start any of them (the session
menu at the bottom right of the password field). It shows the prompts of
[security keys](#signing-in-with-a-security-key-yubikey). Left at the login
screen, GDM suspends the computer after about 20 minutes; to prevent that on a
machine (e.g. one you reach over SSH after a reboot), add to its `modules`:

```nix
{ services.displayManager.gdm.autoSuspend = false; }
```

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
`lib.mkIf (config.nixos-central.desktop == "<name>")`. The GDM login screen,
sound, Bluetooth and printing for every graphical desktop come from
`modules/base/graphical.nix`.

## NVIDIA graphics

The installer finds NVIDIA GPUs, offers the driver, and records the result in the
`nvidia` fact of `/etc/nixos/flake.nix`. To add it to an existing machine, set the
fact yourself, run `sudo nixos-rebuild boot --flake /etc/nixos` and reboot.

```nix
nvidia = null;                        # no NVIDIA driver
nvidia = { };                         # NVIDIA GPU driving the displays, e.g. a desktop
nvidia = {                            # hybrid laptop
  intelBusId = "PCI:0@0:2:0";         # or amdgpuBusId
  nvidiaBusId = "PCI:1@0:0:0";
};
```

Every NVIDIA machine uses NVIDIA's **open kernel modules** with its proprietary
userspace, so the GPU must be a Turing or newer one (RTX, GTX 16xx or newer). Bus
IDs are decimal, while `lspci` shows them in hexadecimal: `0a:00.0` is
`PCI:10@0:0:0`.

The installer only records bus IDs for a machine with an integrated Intel or AMD
GPU and a battery. On such a **hybrid laptop**, the desktop renders on the
integrated GPU, and the NVIDIA GPU powers down until a program uses it. Run a
program on the NVIDIA GPU with:

```sh
nvidia-offload <program>
```

**Containers** reach the GPU through its CDI device name. Docker's `--gpus` option
and `runtime: nvidia` in compose files aren't set up for this:

```sh
docker run --rm --device nvidia.com/gpu=all <image> nvidia-smi
```

**Driver channel.** Add `channel` to the fact to choose where the driver comes
from:

```nix
nvidia = { channel = "unstable"; };   # can be combined with bus IDs
```

| Channel | Driver | Built on the machine |
|---|---|---|
| `"stable"` (default) | production driver of this repository's nixpkgs release | userspace package |
| `"unstable"` | newest driver of nixos-unstable, against the machine's own kernel | userspace package and kernel modules |

Both download the driver from NVIDIA during the install and when it changes. An
unstable driver has more that can go wrong: if it stops building for the machine,
the machine keeps running but gets no updates until that's fixed.
`nix flake check` builds the drivers of both channels, so an update that breaks
either one stays out of `main` until someone resolves it.

`nixos-central upgrade` activates a new driver while the old kernel modules are
still loaded, and says so: programs using the GPU may fail until you reboot. The
daily update only takes effect after a reboot, so it doesn't have this problem.

## Signing in with a security key (YubiKey)

On every graphical desktop you can log in and unlock the screen by touching a
FIDO2/U2F security key (e.g. a YubiKey) **instead of typing your password**.
The password keeps working everywhere, with or without the key. Console (TTY)
login and `sudo` always ask for the password. Machines with desktop `none`
don't support keys.

Enroll a key once (plug it in, run this, touch the key when it blinks):

```sh
mkdir -p ~/.config/Yubico
pamu2fcfg -o pam://nixos-central -i pam://nixos-central > ~/.config/Yubico/u2f_keys
```

It works right away, no rebuild needed. Keep the `-o … -i …` part: it binds
the key to all nixos-central machines rather than to this one.

- **Backup key**: plug in the second key and add it to the same file
  (note `-n` and `>>`):

  ```sh
  pamu2fcfg -n -o pam://nixos-central -i pam://nixos-central >> ~/.config/Yubico/u2f_keys
  ```
- **Your other machines**: copy `~/.config/Yubico/u2f_keys` to the same place
  there; no need to enroll again.
- **Lost key**: the file has one line, `<user>:<key>:<key>…`, with no way to
  tell the keys apart, so create it again with the keys you still have (the
  enrollment command above, then the backup command for each further key).
  Removing the file turns key login off entirely.

Where the key works:

| Desktop | Login screen | Lock screen |
|---|---|---|
| `kde` | GDM: choose your account, touch the key when asked | touch the key, then click *Unlock* |
| `gnome` | GDM: choose your account, touch the key when asked | same |
| `niri-noctalia` | GDM: choose your account, touch the key when asked | Noctalia: touch the key when asked (see below) |

On `niri-noctalia`, turn on *Settings → Lock Screen → Behavior → Auto-start
authentication* in Noctalia once: the lock screen then asks for the key right
away. Without it, press Enter on the empty password field first, then touch
the key.

Touch the key only when asked: a YubiKey touched at other times types a
one-time code into the focused field (the random characters you may see). If
you don't use that code, turn it off on the key with
`ykman config usb --disable OTP` (package `yubikey-manager`).

**Security note:** whoever holds an enrolled key can unlock your graphical
session without your password; no PIN is asked. Keep the key with you, and
remove a lost key from the file on every machine.

## Tailscale

Every machine runs the [Tailscale](https://tailscale.com) daemon. It stays
idle until you sign in once, without sudo:

```sh
tailscale up
```

The sign-in stays on the machine (`/var/lib/tailscale`), never in a
repository; `tailscale logout` signs the machine out again. A tray app is up
to your profile (e.g. `ktailctl` on KDE).

On [other distributions](#install-on-another-linux-distribution), install
Tailscale from the distribution or with
`curl -fsSL https://tailscale.com/install.sh | sh`; a home can't run the
daemon.

## Users and profiles

The primary user's environment is built with [home-manager](https://github.com/nix-community/home-manager)
from two parts:

- the **base configuration** from this repository, `modules/home/base.nix`
  (bash, git, Firefox, vim, htop, wget, unzip; `EDITOR=vim`), which every user
  gets, and
- the user's **profile** from their [private overlay](#private-overlay), if the
  machine has one. This repository holds no personal profiles.

The overlay profile is chosen by the user's name, unless the machine flake
records a different profile next to `user`, so one generic overlay profile can
serve any user:

```nix
user = "alice";
profile = "developer"; # profile of the private overlay
```

Here `alice` gets the base configuration plus the overlay's `developer`
profile; her login name and home directory stay `alice`. The installer writes
this line when you choose an overlay profile;
`nixos-central private setup --profile` adds it later, and
`nixos-central private remove` takes it out again. Without an overlay, a
recorded profile has no effect and the build warns about it.

This is decided every time the system is built, so a profile added to the
overlay later is picked up by the machine's next update. The base
configuration only sets defaults; a profile overrides them by setting the same
option, without `lib.mkForce`:

```nix
# homeModules.alice of your private overlay
{ pkgs, ... }:
{
  home.packages = [ pkgs.gimp ];
  home.sessionVariables.EDITOR = "nano";
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
your [private overlay](#private-overlay).

Permanent changes for every user (the base configuration, shared modules) go
through a pull request to this repository. To try a package without changing anything:

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
| `general-tools.nix` | everyday CLI utilities: `rsync`, `dust`, `ncdu`, `whois`, `iftop`, `nslookup`/`dig` |
| `git.nix` | git with Git LFS; rebase on pull, push sets the upstream |
| `zsh.nix` | zsh with completion, autosuggestions, syntax highlighting, shared history |

Pick modules by name with `centralModules`, which every profile and private
overlay receives:

```nix
# homeModules.default of your private overlay
{ centralModules, ... }:
{
  imports = with centralModules; [ general-tools git zsh ];
}
```

The module names are an interface for overlays: renaming or removing one is a
breaking change. The base configuration includes none of them.

The modules set no names or emails; put those in your overlay. Their workflow
defaults (e.g. git's) are overridden by setting the same option:

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
prints the `chsh` command instead. Selecting a shell installs it; for zsh,
import the `zsh` module as well for the configuration above.

### Private overlay

Your own setup lives in a private repository you control: which shared
modules you use, your login shell, name and email, fonts and themes, and files
that must not be public (work SSH configuration, internal scripts). It is added
to a machine during installation (see [Install](#install)) or afterwards, and
applied on top of the base configuration.

The overlay is a flake **without inputs** that only exports modules, one per
profile; packages and options come from this repository. It can hold several
people's profiles:

```nix
# flake.nix in your private repository
{
  outputs = _: {
    homeModules.alice = { centralModules, pkgs, ... }: {
      imports = with centralModules; [ general-tools git zsh ];
      nixos-central.shell = "zsh";
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

The profile is chosen by name: the recorded `profile` if the local flake has
one, otherwise the user's name. So a generic profile such as
`developer` can serve anyone who records it. Without a matching
profile, `homeModules.default` is used; if that doesn't exist either, the build
fails and lists the overlay's profiles.

To set it up later, after the first boot (NixOS) or after `home-only.sh` (other
distributions):

1. Copy your SSH key to `~/.ssh/id_ed25519`. It must have no passphrase,
   because daily updates fetch the overlay without you. Its public key must be
   added to your GitHub account.
2. Run:

   ```sh
   nixos-central private setup git+ssh://git@github.com/alice/private
   ```

   It checks that the key can read the repository, adds the overlay to
   `/etc/nixos/flake.nix` (or `~/.config/home-manager/flake.nix`) and
   activates it. If anything fails, the flake is left as it was.

   Without a URL it sets up the shared overlay
   `git+ssh://git@github.com/tran-engineering/nixos-central-private`
   (`nixos-central private setup`). A fork changes this default in
   `nixos-central-internal/lib/default-private.nix`.

   Add `--profile NAME` to use a profile other than your user's name, e.g. a
   generic `developer` profile:

   ```sh
   nixos-central private setup git+ssh://git@github.com/alice/private --profile developer
   ```

   This records `profile = "developer";` next to `user` in the local flake;
   `nixos-central private remove` takes it out again together with the
   overlay.

`nixos-central private` shows which overlay a machine or home uses, if any.

From then on, daily updates and `nixos-central upgrade` update the overlay
together with this repository. On NixOS they run as root, which uses your
`~/.ssh/id_ed25519` for GitHub only. After pushing a change to the overlay,
`nixos-central upgrade --private` uses it right away without updating this
repository.

If the overlay can't be fetched (key removed from GitHub, repository renamed),
updates **stop** instead of continuing without it: the machine keeps running
its current configuration, and `systemctl status nixos-upgrade` shows the
error. Fix access, or take the overlay out with `nixos-central private remove`.

Losing a machine means its key can read the repository: remove that key from
your GitHub account.

## Installing apps

Apps you want on every machine belong in your profile (`home.packages`), so
they come from nixpkgs and follow the updates and rollbacks below. For apps
that nixpkgs lacks, or to try something on one machine, every graphical
desktop (all except `none`) also has:

- **Flatpak with [Flathub](https://flathub.org)**, already set up:
  - KDE: Discover, GNOME: GNOME Software (*Software*); search and install.
  - Any desktop, in a terminal:

    ```sh
    flatpak search spotify
    flatpak install flathub com.spotify.Client   # asks for your password (all users)
    flatpak install --user flathub com.spotify.Client   # only for you, no password
    flatpak uninstall com.spotify.Client
    ```

  Installed apps appear in the application launcher (after logging in again,
  the first time). They are **updated automatically** a few minutes after each start
  (and, for `--user` installs, after logging in) and then every day, separately
  from the system update and without a reboot. To keep an app at its version,
  `sudo flatpak mask com.spotify.Client` (`flatpak mask --user …` for a
  `--user` install; undo with `--remove`).

  Flatpak apps are outside Nix: they exist only on the machine you installed
  them on, stay as they are when you boot an older generation, and don't show
  up in `nixos-central diff`. Their data is in `/var/lib/flatpak` (or
  `~/.local/share/flatpak` for `--user`).
- **AppImages** run directly: make the downloaded file executable
  (`chmod +x App.AppImage`, or in the file manager's properties) and start it
  with `./App.AppImage` or a double-click.

## Scripts from other distributions

Scripts written for other distributions run unchanged, even when they
hard-code paths like `#!/bin/bash`, `#!/usr/bin/python3` or `/usr/bin/git`.
On every machine, `/usr/bin/<name>` and `/bin/<name>` lead to the program
`<name>` that the running program would find on its `PATH`:

```sh
/usr/bin/bash --version                        # the system's bash
/usr/bin/hello                                 # No such file or directory: not installed
nix shell nixpkgs#hello -c /usr/bin/hello      # found: hello is on PATH in this shell
```

So what shows up depends on who asks: a program from your profile or a
`nix shell` is there for you, but not for root or for system services.
`/bin/sh`, `/usr/bin/env`, `/bin/bash` and `/usr/bin/bash` always work, also
without a `PATH`. `ls /usr/bin` shows an empty directory; the programs are
found only when asked for by name.

This covers paths only: prebuilt programs downloaded for other distributions
(not scripts) usually still don't start, as they expect libraries in
`/usr/lib`. Use a Nix package, Flatpak or an AppImage for those.

## The nixos-central command

Everything you do by hand with a machine or a standalone home goes through one
command:

```sh
nixos-central                 # in a terminal: pick a subcommand from a menu
nixos-central --help          # list the subcommands
nixos-central upgrade         # update now (see below)
nixos-central diff            # what the pending (or else the last) update changes
nixos-central status          # when the last update succeeded
nixos-central private         # show, add (setup) or remove the private overlay
nixos-central try <branch>    # NixOS only: try a branch until the next reboot
```

Subcommands and their options complete with Tab in bash, zsh and fish. The
menu runs the chosen subcommand without arguments; `try` isn't in it because
it needs a branch.

## Updates

- Every day (or soon after boot, if the computer was off) each machine fetches
  the latest `main` of this repository, builds it and makes it the **default for
  the next boot**. The running system is not changed and the computer is never
  rebooted automatically.
- Desktop users get a notification *"Update ready – reboot when convenient"*.
- See which packages an update changes (as `nh` shows them): `nixos-central diff`.
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
- Install the latest update **and use it now**: `nixos-central upgrade`. It
  also becomes the default for the next boot. Switching may restart services
  (and the desktop), so save your work first. A new kernel is used only after
  the next reboot; the command says so when that applies.
  `nixos-central upgrade --private` updates only your
  [private overlay](#private-overlay) and leaves this repository at the
  installed revision. Standalone homes have the same command (no `sudo`).
- When no update has succeeded for more than 7 days, every new terminal says so,
  with what to do (reboot into a staged update, run `nixos-central upgrade`, or
  check the daily update). It also shows how old the running system and the
  pinned revision of this repository are. A successful daily update counts even
  if nothing changed, so a quiet repository causes no notice. Homes on
  [other distributions](#install-on-another-linux-distribution) get the same
  notice. `nixos-central status` shows the same at any time. Change the
  number of days in your profile, `0` turns the terminal notice off:

  ```nix
  nixos-central.updateNotice.days = 14;
  ```

### Firmware updates

Firmware (UEFI/BIOS, SSDs, docks, …) is updated through
[fwupd](https://fwupd.org) from the Linux Vendor Firmware Service. Every
machine refreshes the list of available updates daily; installing them is up to
you, because a firmware update often needs a reboot and can't be undone by
choosing an older generation. Keep laptops on power while updating.

- KDE: Discover lists firmware updates next to the others.
- GNOME: GNOME Software (*Software*, Updates tab) or the *Firmware* app.
- Any desktop, in a terminal:

  ```sh
  fwupdmgr get-updates   # what's available
  fwupdmgr update        # install; asks before rebooting
  ```

Not every vendor publishes firmware there; `fwupdmgr get-devices` shows which
devices of the machine fwupd can update.

### Trying a branch

```sh
nixos-central try my-branch
```

Activates this machine's configuration built from `my-branch` of this repository
**until the next reboot**. It creates no boot entry and does not change
`/etc/nixos`. Typical flow: push a branch with your profile changes, try it,
open a pull request when happy.

## Development

```sh
nix flake check                       # evaluates and builds sample hosts, runs VM tests
nix build .#checks.x86_64-linux.shells
nix build .#desktopTests.reboot-notify-kde   # full desktop tests (kde, gnome, niri-noctalia), not in flake check (10–15 min each)
nix run --impure -f nixos-central-internal/tests/e2e   # full installer test in QEMU (needs KVM + internet)
nix build .#packages.x86_64-linux.iso   # installation image (published by .github/workflows/iso.yml)
shellcheck nixos-central-internal/installer/install.sh
shellcheck nixos-central-internal/installer/home-only.sh
```

Sample hosts used in CI: `ci-gnome`, `ci-kde`, `ci-niri-noctalia`, `ci-none`
(`nixosConfigurations`, not meant to be installed). Sample standalone homes:
`ci-home-default` (base configuration only), `ci-home-dotted`, `ci-home-aarch64`,
`ci-home-modules-aarch64` (`homeConfigurations`). Test profiles live in
`nixos-central-internal/tests/profiles/` and are added only by these CI
configurations: `ci-user` (overrides one base setting) and `ci-modules`, which
uses every shared module and is evaluated on NixOS and standalone
(`host-eval-ci-modules`, `home-eval-ci-modules`). `host-profile` and
`overlay-profiles` test how a recorded profile selects the overlay profile. `central-modules` guards the module names overlays
rely on; `overlay-eval` and `overlay-rejects-inputs` test private overlays with
`nixos-central-internal/tests/overlay`. These checks don't build packages;
those come from the NixOS binary cache.
The update notification is tested headless with a stub notification server
(`reboot-notify`); `desktopTests.reboot-notify-kde`, `-gnome` and
`-niri-noctalia` check it in a real desktop session and are run by hand, as CI
runs only the flake checks. CI (`.github/workflows/checks.yml`) doesn't run
`nix flake check` itself: evaluating every check in one process takes about
19 GB, more than a hosted runner has. It spreads the checks over several
runners, evaluates each in its own Nix process and builds at most two at a
time. The niri test also checks that Noctalia loads on
the first login into a fresh home.
`desktop-apps` checks Flatpak, the Flathub remote and the update timers
offline and the AppImage registration, on a machine without desktop and with
the switch set by hand; installing from Flathub and the app stores need
network and are checked by hand.
`envfs` checks that `/usr/bin/<name>` and `/bin/<name>` follow the caller's
`PATH` (also inside `nix shell`) and that `sh`, `env` and `bash` resolve without
one, including from a service.
`u2f-pam` checks which generated PAM services accept a security key (login
and lock screens) and which must not (`login`, `sudo`, `su`, desktop `none`);
signing in with a real key is checked by hand.
