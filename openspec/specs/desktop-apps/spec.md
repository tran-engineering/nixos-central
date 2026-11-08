# desktop-apps Specification

## Purpose

Lets users of graphical machines install and run desktop apps that are not in
nixpkgs or not in their profile, through Flatpak (Flathub) and AppImages,
without changing the machine's Nix configuration.

## Requirements

### Requirement: Flatpak with Flathub on graphical desktops
Every machine with a graphical desktop (every desktop except `none`) SHALL provide Flatpak with the Flathub remote configured system-wide, so that a user can install a Flathub app without first adding a remote. Machines with desktop `none` MUST NOT have Flatpak.

#### Scenario: Install an app from the command line
- **WHEN** a user on a `kde`, `gnome` or `niri-noctalia` machine with network access runs `flatpak install flathub <app-id>`
- **THEN** the app is installed from Flathub and can be started from the desktop's application launcher

#### Scenario: Flathub configured without network at boot
- **WHEN** a graphical machine boots without network access and later gets connected
- **THEN** the Flathub remote is configured without the user doing anything, and the boot is not delayed or marked failed because of it

#### Scenario: No graphical desktop
- **WHEN** a machine uses desktop `none`
- **THEN** the `flatpak` command is not installed

### Requirement: App store on KDE and GNOME
On `kde` and `gnome` machines, the desktop's app store (Discover on KDE, GNOME Software on GNOME) SHALL list Flathub apps and install them.

#### Scenario: Install an app from Discover
- **WHEN** a user on a `kde` machine searches for a Flathub app in Discover and installs it
- **THEN** the app is installed from Flathub

#### Scenario: Install an app from GNOME Software
- **WHEN** a user on a `gnome` machine opens GNOME Software
- **THEN** it lists Flathub apps and can install them

### Requirement: Daily automatic Flatpak updates
On graphical machines, installed Flatpak apps and runtimes SHALL be updated automatically at least once a day, without user interaction and without a reboot. An update SHALL also run a few minutes after each boot, without delaying the boot. A failed update MUST leave the installed apps usable.

#### Scenario: Newer app version on Flathub
- **WHEN** a newer version of an installed Flatpak app is published on Flathub
- **THEN** it is installed within a day while the machine is on and online, and is used from the app's next start

#### Scenario: Machine that is off most days
- **WHEN** a machine is switched on after being off, and a newer version of an installed app is on Flathub
- **THEN** the newer version is installed within the first hour after boot while online, and the boot does not wait for it

#### Scenario: Update without network
- **WHEN** the daily Flatpak update runs while the machine is offline
- **THEN** the installed apps stay as they are and keep working

### Requirement: Flatpak apps are independent of system generations
Flatpak apps SHALL stay installed and usable across system upgrades and across booting an older system generation. They are not part of the repository's configuration: the automatic NixOS upgrade MUST NOT install or remove Flatpak apps.

#### Scenario: Boot an older generation
- **WHEN** a user with installed Flatpak apps boots the previous system generation from the boot menu
- **THEN** the same Flatpak apps are installed and start

### Requirement: AppImages run directly
On every graphical machine, a user SHALL be able to start an AppImage (type 1 or type 2) by executing the file, without installing anything and without a wrapper command. Machines with desktop `none` MUST NOT get this.

#### Scenario: Run a downloaded AppImage
- **WHEN** a user on a graphical machine marks a downloaded `.AppImage` file executable and runs it
- **THEN** the application starts

#### Scenario: AppImage on a machine without desktop
- **WHEN** a machine uses desktop `none`
- **THEN** no AppImage support is installed
